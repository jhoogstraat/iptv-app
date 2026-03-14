//
//  StreamListCache.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation

nonisolated struct StreamListCacheKey: Codable, Hashable, Sendable {
    let providerFingerprint: String
    let contentType: XtreamContentType
    let categoryID: String
    let pageToken: String?

    var rawKey: String {
        [providerFingerprint, contentType.rawValue, categoryID, pageToken ?? "all"].joined(separator: "|")
    }

    var fileName: String {
        rawKey.sha256Hex + ".json"
    }
}

nonisolated struct CachedVideoDTO: Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let containerExtension: String
    let contentType: String
    let coverImageURL: String?
    let tmdbId: String?
    let rating: Double?
    let added: String?

    init(
        id: Int,
        name: String,
        containerExtension: String,
        contentType: String,
        coverImageURL: String?,
        tmdbId: String?,
        rating: Double?,
        added: String? = nil
    ) {
        self.id = id
        self.name = name
        self.containerExtension = containerExtension
        self.contentType = contentType
        self.coverImageURL = coverImageURL
        self.tmdbId = tmdbId
        self.rating = rating
        self.added = added
    }
}

nonisolated struct StreamListCacheEntry: Codable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let key: StreamListCacheKey
    let savedAt: Date
    let lastAccessAt: Date
    let videos: [CachedVideoDTO]

    init(key: StreamListCacheKey, savedAt: Date, lastAccessAt: Date, videos: [CachedVideoDTO]) {
        self.schemaVersion = Self.schemaVersion
        self.key = key
        self.savedAt = savedAt
        self.lastAccessAt = lastAccessAt
        self.videos = videos
    }

    func touching(at date: Date) -> StreamListCacheEntry {
        StreamListCacheEntry(key: key, savedAt: savedAt, lastAccessAt: date, videos: videos)
    }
}

nonisolated protocol StreamListCacheStore: Sendable {
    func load(key: StreamListCacheKey) async throws -> StreamListCacheEntry?
    func save(_ entry: StreamListCacheEntry, for key: StreamListCacheKey) async throws
    func entries(providerFingerprint: String) async throws -> [StreamListCacheEntry]
    func pruneCacheIfNeeded() async throws
    func removeValue(for key: StreamListCacheKey) async throws
    func removeAll(for providerFingerprint: String) async throws
}

actor DiskStreamListCacheStore: StreamListCacheStore {
    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let maxCacheBytes: Int

    init(
        directoryURL: URL? = nil,
        maxCacheBytes: Int = 100 * 1024 * 1024
    ) {
        let baseDirectory = directoryURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directoryURL = baseDirectory.appending(path: "StreamListCache", directoryHint: .isDirectory)
        self.maxCacheBytes = maxCacheBytes
    }

    func load(key: StreamListCacheKey) async throws -> StreamListCacheEntry? {
        try ensureDirectoryExists()
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path()) else { return nil }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let entry = try JSONDecoder().decode(StreamListCacheEntry.self, from: data)
            guard entry.schemaVersion == StreamListCacheEntry.schemaVersion, entry.key == key else {
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

    func save(_ entry: StreamListCacheEntry, for key: StreamListCacheKey) async throws {
        try ensureDirectoryExists()
        let url = fileURL(for: key)
        let data = try JSONEncoder().encode(entry)
        try data.write(to: url, options: [.atomic])
        touchFile(at: url)
        try await pruneCacheIfNeeded()
    }

    func pruneCacheIfNeeded() async throws {
        try ensureDirectoryExists()

        var files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        struct FileRecord {
            let url: URL
            let size: Int
            let modifiedAt: Date
        }

        var records: [FileRecord] = []
        records.reserveCapacity(files.count)
        var totalSize = 0

        for file in files {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let size = values.fileSize ?? 0
            totalSize += size
            records.append(FileRecord(url: file, size: size, modifiedAt: values.contentModificationDate ?? .distantPast))
        }

        guard totalSize > maxCacheBytes else { return }

        records.sort { $0.modifiedAt < $1.modifiedAt }

        for record in records where totalSize > maxCacheBytes {
            try? fileManager.removeItem(at: record.url)
            totalSize -= record.size
        }

        files.removeAll(keepingCapacity: false)
    }

    func entries(providerFingerprint: String) async throws -> [StreamListCacheEntry] {
        try ensureDirectoryExists()

        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let decoder = JSONDecoder()
        return files.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let entry = try? decoder.decode(StreamListCacheEntry.self, from: data),
                  entry.key.providerFingerprint == providerFingerprint else {
                return nil
            }
            return entry
        }
    }

    func removeValue(for key: StreamListCacheKey) async throws {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path()) else { return }
        try? fileManager.removeItem(at: url)
    }

    func removeAll(for providerFingerprint: String) async throws {
        let providerEntries = try await entries(providerFingerprint: providerFingerprint)
        for entry in providerEntries {
            try? fileManager.removeItem(at: fileURL(for: entry.key))
        }
    }

    private func fileURL(for key: StreamListCacheKey) -> URL {
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

actor CatalogCacheManager {
    private struct InFlightLoad {
        let id: UUID
        let task: Task<[CachedVideoDTO], Error>
    }

    private var memoryCache: [StreamListCacheKey: StreamListCacheEntry] = [:]
    private var inFlightTasks: [StreamListCacheKey: InFlightLoad] = [:]

    private let diskStore: StreamListCacheStore
    private let now: @Sendable () -> Date

    init(
        diskStore: StreamListCacheStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.diskStore = diskStore ?? DiskStreamListCacheStore()
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

    func pruneCacheIfNeeded() async throws {
        try await diskStore.pruneCacheIfNeeded()
    }

    func cachedValue(
        for key: StreamListCacheKey
    ) async throws -> CatalogCachedValue<[CachedVideoDTO]>? {
        let currentDate = now()

        if let memoryEntry = memoryCache[key] {
            let touched = memoryEntry.touching(at: currentDate)
            memoryCache[key] = touched
            return CatalogCachedValue(
                value: touched.videos,
                savedAt: touched.savedAt
            )
        }

        guard let diskEntry = try await diskStore.load(key: key) else { return nil }
        memoryCache[key] = diskEntry
        return CatalogCachedValue(
            value: diskEntry.videos,
            savedAt: diskEntry.savedAt
        )
    }

    func refreshValue(
        for key: StreamListCacheKey,
        fetcher: @escaping @Sendable () async throws -> [CachedVideoDTO]
    ) async throws -> [CachedVideoDTO] {
        if let inFlight = inFlightTasks[key] {
            return try await inFlight.task.value
        }

        let inFlight = startFetch(for: key, fetcher: fetcher)
        return try await inFlight.task.value
    }

    func entries(providerFingerprint: String) async throws -> [StreamListCacheEntry] {
        try await diskStore.entries(providerFingerprint: providerFingerprint)
    }

    func entry(for key: StreamListCacheKey) async throws -> StreamListCacheEntry? {
        let currentDate = now()

        if let memoryEntry = memoryCache[key] {
            let touched = memoryEntry.touching(at: currentDate)
            memoryCache[key] = touched
            return touched
        }

        guard let diskEntry = try await diskStore.load(key: key) else { return nil }
        memoryCache[key] = diskEntry
        return diskEntry
    }

    func removeValue(for key: StreamListCacheKey) async throws {
        inFlightTasks[key]?.task.cancel()
        inFlightTasks[key] = nil
        memoryCache[key] = nil
        try await diskStore.removeValue(for: key)
    }

    func removeAll(for providerFingerprint: String) async throws {
        memoryCache = memoryCache.filter { $0.key.providerFingerprint != providerFingerprint }
        try await diskStore.removeAll(for: providerFingerprint)
    }

    func loadStreamList(
        for key: StreamListCacheKey,
        force: Bool = false,
        fetcher: @escaping @Sendable () async throws -> [CachedVideoDTO]
    ) async throws -> [CachedVideoDTO] {
        if !force {
            if let entry = try await entry(for: key) {
                return entry.videos
            }
        }

        if let inFlight = inFlightTasks[key] {
            return try await inFlight.task.value
        }

        let inFlight = startFetch(for: key, fetcher: fetcher)
        return try await inFlight.task.value
    }

    private func startFetch(
        for key: StreamListCacheKey,
        fetcher: @escaping @Sendable () async throws -> [CachedVideoDTO]
    ) -> InFlightLoad {
        let loadID = UUID()
        let loadTask = Task(priority: .utility) {
            try await fetcher()
        }

        let inFlight = InFlightLoad(id: loadID, task: loadTask)
        inFlightTasks[key] = inFlight

        Task(priority: .utility) {
            do {
                let videos = try await loadTask.value
                await self.storeNetworkResult(videos, for: key)
            } catch {
                // Keep stale cache on failure. Callers can fallback to stale entries.
            }
            await self.finishInFlightTask(for: key, loadID: loadID)
        }

        return inFlight
    }

    private func storeNetworkResult(_ videos: [CachedVideoDTO], for key: StreamListCacheKey) async {
        let currentDate = now()
        let entry = StreamListCacheEntry(key: key, savedAt: currentDate, lastAccessAt: currentDate, videos: videos)
        memoryCache[key] = entry
        try? await diskStore.save(entry, for: key)
    }

    private func finishInFlightTask(for key: StreamListCacheKey, loadID: UUID) {
        guard let current = inFlightTasks[key], current.id == loadID else { return }
        inFlightTasks[key] = nil
    }
}

protocol ImagePrefetching: Sendable {
    func prefetch(urls: [URL]) async
}

nonisolated struct NoopImagePrefetcher: ImagePrefetching {
    func prefetch(urls: [URL]) async { }
}

nonisolated enum ProviderCacheFingerprint {
    static func make(from config: ProviderConfig) -> String {
        "\(config.apiURL.absoluteString)|\(config.username)".sha256Hex
    }
}
