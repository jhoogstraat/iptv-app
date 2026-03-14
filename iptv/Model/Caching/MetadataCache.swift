//
//  MetadataCache.swift
//  iptv
//
//  Created by Codex on 10.03.26.
//

import Foundation

nonisolated enum CatalogMetadataKind: String, Codable, Sendable {
    case vodCategories
    case seriesCategories
    case vodInfo
    case seriesInfo
}

nonisolated struct CatalogMetadataCacheKey: Codable, Hashable, Sendable {
    let providerFingerprint: String
    let kind: CatalogMetadataKind
    let resourceID: String

    var rawKey: String {
        [providerFingerprint, kind.rawValue, resourceID].joined(separator: "|")
    }

    var fileName: String {
        rawKey.sha256Hex + ".json"
    }
}

nonisolated struct CatalogMetadataCacheEntry: Codable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let key: CatalogMetadataCacheKey
    let savedAt: Date
    let lastAccessAt: Date
    let payload: Data

    init(key: CatalogMetadataCacheKey, savedAt: Date, lastAccessAt: Date, payload: Data) {
        self.schemaVersion = Self.schemaVersion
        self.key = key
        self.savedAt = savedAt
        self.lastAccessAt = lastAccessAt
        self.payload = payload
    }

    func touching(at date: Date) -> CatalogMetadataCacheEntry {
        CatalogMetadataCacheEntry(key: key, savedAt: savedAt, lastAccessAt: date, payload: payload)
    }
}

nonisolated struct CatalogCachedValue<Value: Sendable>: Sendable {
    let value: Value
    let savedAt: Date
    let isStale: Bool
}

nonisolated protocol CatalogMetadataCacheStore: Sendable {
    func load(key: CatalogMetadataCacheKey) async throws -> CatalogMetadataCacheEntry?
    func save(_ entry: CatalogMetadataCacheEntry, for key: CatalogMetadataCacheKey) async throws
    func entries(providerFingerprint: String) async throws -> [CatalogMetadataCacheEntry]
    func removeAll(for providerFingerprint: String) async throws
    func pruneCacheIfNeeded() async throws
}

actor DiskCatalogMetadataCacheStore: CatalogMetadataCacheStore {
    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let maxCacheBytes: Int

    init(
        directoryURL: URL? = nil,
        maxCacheBytes: Int = 32 * 1024 * 1024
    ) {
        let baseDirectory = directoryURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directoryURL = baseDirectory.appending(path: "CatalogMetadataCache", directoryHint: .isDirectory)
        self.maxCacheBytes = maxCacheBytes
    }

    func load(key: CatalogMetadataCacheKey) async throws -> CatalogMetadataCacheEntry? {
        try ensureDirectoryExists()
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path()) else { return nil }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let entry = try JSONDecoder().decode(CatalogMetadataCacheEntry.self, from: data)
            guard entry.schemaVersion == CatalogMetadataCacheEntry.schemaVersion, entry.key == key else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            touchFile(at: url)
            return entry.touching(at: Date())
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    func save(_ entry: CatalogMetadataCacheEntry, for key: CatalogMetadataCacheKey) async throws {
        try ensureDirectoryExists()
        let data = try JSONEncoder().encode(entry)
        let url = fileURL(for: key)
        try data.write(to: url, options: [.atomic])
        touchFile(at: url)
        try await pruneCacheIfNeeded()
    }

    func entries(providerFingerprint: String) async throws -> [CatalogMetadataCacheEntry] {
        try ensureDirectoryExists()
        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let decoder = JSONDecoder()
        return files.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let entry = try? decoder.decode(CatalogMetadataCacheEntry.self, from: data),
                  entry.key.providerFingerprint == providerFingerprint else {
                return nil
            }
            return entry
        }
    }

    func removeAll(for providerFingerprint: String) async throws {
        let providerEntries = try await entries(providerFingerprint: providerFingerprint)
        for entry in providerEntries {
            try? fileManager.removeItem(at: fileURL(for: entry.key))
        }
    }

    func pruneCacheIfNeeded() async throws {
        try ensureDirectoryExists()

        struct FileRecord {
            let url: URL
            let size: Int
            let modifiedAt: Date
        }

        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var records: [FileRecord] = []
        var totalSize = 0

        for file in files {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let size = values.fileSize ?? 0
            totalSize += size
            records.append(
                FileRecord(
                    url: file,
                    size: size,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }

        guard totalSize > maxCacheBytes else { return }

        for record in records.sorted(by: { $0.modifiedAt < $1.modifiedAt }) where totalSize > maxCacheBytes {
            try? fileManager.removeItem(at: record.url)
            totalSize -= record.size
        }
    }

    private func fileURL(for key: CatalogMetadataCacheKey) -> URL {
        directoryURL.appending(path: key.fileName)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: directoryURL.path()) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func touchFile(at url: URL) {
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path())
    }
}

actor CatalogMetadataCacheManager {
    private struct InFlightLoad {
        let id: UUID
        let task: Task<Data, Error>
    }

    private var memoryCache: [CatalogMetadataCacheKey: CatalogMetadataCacheEntry] = [:]
    private var inFlightTasks: [CatalogMetadataCacheKey: InFlightLoad] = [:]

    private let diskStore: CatalogMetadataCacheStore
    private let now: @Sendable () -> Date

    init(
        diskStore: CatalogMetadataCacheStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.diskStore = diskStore ?? DiskCatalogMetadataCacheStore()
        self.now = now

        Task(priority: .utility) {
            try? await self.diskStore.pruneCacheIfNeeded()
        }
    }

    func clearMemoryCache() {
        inFlightTasks.values.forEach { $0.task.cancel() }
        inFlightTasks.removeAll()
        memoryCache.removeAll()
    }

    func cachedPayload(
        for key: CatalogMetadataCacheKey,
        ttl: TimeInterval
    ) async throws -> CatalogCachedValue<Data>? {
        let currentDate = now()

        if let memoryEntry = memoryCache[key] {
            let touched = memoryEntry.touching(at: currentDate)
            memoryCache[key] = touched
            return CatalogCachedValue(
                value: touched.payload,
                savedAt: touched.savedAt,
                isStale: isStale(touched.savedAt, ttl: ttl, at: currentDate)
            )
        }

        guard let diskEntry = try await diskStore.load(key: key) else { return nil }
        memoryCache[key] = diskEntry

        return CatalogCachedValue(
            value: diskEntry.payload,
            savedAt: diskEntry.savedAt,
            isStale: isStale(diskEntry.savedAt, ttl: ttl, at: currentDate)
        )
    }

    func refreshPayload(
        for key: CatalogMetadataCacheKey,
        fetcher: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        if let inFlight = inFlightTasks[key] {
            return try await inFlight.task.value
        }

        let loadID = UUID()
        let loadTask = Task(priority: .utility) { try await fetcher() }
        inFlightTasks[key] = InFlightLoad(id: loadID, task: loadTask)

        do {
            let data = try await loadTask.value
            let currentDate = now()
            let entry = CatalogMetadataCacheEntry(key: key, savedAt: currentDate, lastAccessAt: currentDate, payload: data)
            memoryCache[key] = entry
            try await diskStore.save(entry, for: key)
            finishInFlightTask(for: key, loadID: loadID)
            return data
        } catch {
            finishInFlightTask(for: key, loadID: loadID)
            throw error
        }
    }

    func entries(providerFingerprint: String) async throws -> [CatalogMetadataCacheEntry] {
        try await diskStore.entries(providerFingerprint: providerFingerprint)
    }

    func removeAll(for providerFingerprint: String) async throws {
        memoryCache = memoryCache.filter { $0.key.providerFingerprint != providerFingerprint }
        try await diskStore.removeAll(for: providerFingerprint)
    }

    private func finishInFlightTask(for key: CatalogMetadataCacheKey, loadID: UUID) {
        guard let current = inFlightTasks[key], current.id == loadID else { return }
        inFlightTasks[key] = nil
    }

    private func isStale(_ savedAt: Date, ttl: TimeInterval, at currentDate: Date) -> Bool {
        currentDate.timeIntervalSince(savedAt) > ttl
    }
}

nonisolated struct CachedCategoryDTO: Codable, Hashable, Sendable {
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ category: XtreamCategory) {
        self.id = category.id
        self.name = category.name
    }

    init(_ category: Category) {
        self.id = category.id
        self.name = category.name
    }
}

nonisolated struct CachedVideoInfoDTO: Codable, Hashable, Sendable {
    let images: [URL]
    let plot: String
    let cast: String
    let director: String
    let genre: String
    let releaseDate: String
    let durationLabel: String
    let runtimeMinutes: Int?
    let ageRating: String
    let country: String
    let rating: Double?
    let streamBitrate: Int?
    let audioDescription: String
    let videoResolution: String
    let videoFrameRate: Double?

    init(
        images: [URL],
        plot: String,
        cast: String,
        director: String,
        genre: String,
        releaseDate: String,
        durationLabel: String,
        runtimeMinutes: Int?,
        ageRating: String,
        country: String,
        rating: Double?,
        streamBitrate: Int?,
        audioDescription: String,
        videoResolution: String,
        videoFrameRate: Double?
    ) {
        self.images = images
        self.plot = plot
        self.cast = cast
        self.director = director
        self.genre = genre
        self.releaseDate = releaseDate
        self.durationLabel = durationLabel
        self.runtimeMinutes = runtimeMinutes
        self.ageRating = ageRating
        self.country = country
        self.rating = rating
        self.streamBitrate = streamBitrate
        self.audioDescription = audioDescription
        self.videoResolution = videoResolution
        self.videoFrameRate = videoFrameRate
    }

    init(_ info: VideoInfo) {
        self.images = info.images
        self.plot = info.plot
        self.cast = info.cast
        self.director = info.director
        self.genre = info.genre
        self.releaseDate = info.releaseDate
        self.durationLabel = info.durationLabel
        self.runtimeMinutes = info.runtimeMinutes
        self.ageRating = info.ageRating
        self.country = info.country
        self.rating = info.rating
        self.streamBitrate = info.streamBitrate
        self.audioDescription = info.audioDescription
        self.videoResolution = info.videoResolution
        self.videoFrameRate = info.videoFrameRate
    }
}

extension Category {
    convenience init(cached: CachedCategoryDTO) {
        self.init(id: cached.id, name: cached.name)
    }
}

extension VideoInfo {
    convenience init(cached: CachedVideoInfoDTO) {
        self.init(
            images: cached.images,
            plot: cached.plot,
            cast: cached.cast,
            director: cached.director,
            genre: cached.genre,
            releaseDate: cached.releaseDate,
            durationLabel: cached.durationLabel,
            runtimeMinutes: cached.runtimeMinutes,
            ageRating: cached.ageRating,
            country: cached.country,
            rating: cached.rating,
            streamBitrate: cached.streamBitrate,
            audioDescription: cached.audioDescription,
            videoResolution: cached.videoResolution,
            videoFrameRate: cached.videoFrameRate
        )
    }
}
