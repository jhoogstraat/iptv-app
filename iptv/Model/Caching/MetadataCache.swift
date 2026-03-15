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
}

nonisolated protocol CatalogMetadataCachePersisting: Sendable {
    func load(key: CatalogMetadataCacheKey) async throws -> CatalogMetadataCacheEntry?
    func save(_ entry: CatalogMetadataCacheEntry, for key: CatalogMetadataCacheKey) async throws
    func entries(providerFingerprint: String) async throws -> [CatalogMetadataCacheEntry]
    func removeValue(for key: CatalogMetadataCacheKey) async throws
    func removeAll(for providerFingerprint: String) async throws
    func pruneCacheIfNeeded() async throws
}

actor CatalogMetadataCacheManager {
    private struct InFlightLoad {
        let id: UUID
        let task: Task<Data, Error>
    }

    private var memoryCache: [CatalogMetadataCacheKey: CatalogMetadataCacheEntry] = [:]
    private var inFlightTasks: [CatalogMetadataCacheKey: InFlightLoad] = [:]

    private let store: any CatalogMetadataCachePersisting
    private let now: @Sendable () -> Date

    init(
        store: any CatalogMetadataCachePersisting,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.now = now

        Task(priority: .utility) {
            try? await self.store.pruneCacheIfNeeded()
        }
    }

    func clearMemoryCache() {
        inFlightTasks.values.forEach { $0.task.cancel() }
        inFlightTasks.removeAll()
        memoryCache.removeAll()
    }

    func cachedPayload(
        for key: CatalogMetadataCacheKey
    ) async throws -> CatalogCachedValue<Data>? {
        let currentDate = now()

        if let memoryEntry = memoryCache[key] {
            let touched = memoryEntry.touching(at: currentDate)
            memoryCache[key] = touched
            return CatalogCachedValue(
                value: touched.payload,
                savedAt: touched.savedAt
            )
        }

        guard let storedEntry = try await store.load(key: key) else { return nil }
        memoryCache[key] = storedEntry

        return CatalogCachedValue(
            value: storedEntry.payload,
            savedAt: storedEntry.savedAt
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
            try await store.save(entry, for: key)
            finishInFlightTask(for: key, loadID: loadID)
            return data
        } catch {
            finishInFlightTask(for: key, loadID: loadID)
            throw error
        }
    }

    func entries(providerFingerprint: String) async throws -> [CatalogMetadataCacheEntry] {
        try await store.entries(providerFingerprint: providerFingerprint)
    }

    func entry(for key: CatalogMetadataCacheKey) async throws -> CatalogMetadataCacheEntry? {
        let currentDate = now()

        if let memoryEntry = memoryCache[key] {
            let touched = memoryEntry.touching(at: currentDate)
            memoryCache[key] = touched
            return touched
        }

        guard let storedEntry = try await store.load(key: key) else { return nil }
        memoryCache[key] = storedEntry
        return storedEntry
    }

    func removeValue(for key: CatalogMetadataCacheKey) async throws {
        inFlightTasks[key]?.task.cancel()
        inFlightTasks[key] = nil
        memoryCache[key] = nil
        try await store.removeValue(for: key)
    }

    func removeAll(for providerFingerprint: String) async throws {
        memoryCache = memoryCache.filter { $0.key.providerFingerprint != providerFingerprint }
        try await store.removeAll(for: providerFingerprint)
    }

    private func finishInFlightTask(for key: CatalogMetadataCacheKey, loadID: UUID) {
        guard let current = inFlightTasks[key], current.id == loadID else { return }
        inFlightTasks[key] = nil
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
