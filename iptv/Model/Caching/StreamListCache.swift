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

nonisolated protocol StreamListCachePersisting: Sendable {
    func load(key: StreamListCacheKey) async throws -> StreamListCacheEntry?
    func save(_ entry: StreamListCacheEntry, for key: StreamListCacheKey) async throws
    func entries(providerFingerprint: String) async throws -> [StreamListCacheEntry]
    func pruneCacheIfNeeded() async throws
    func removeValue(for key: StreamListCacheKey) async throws
    func removeAll(for providerFingerprint: String) async throws
}

actor CatalogCacheManager {
    private struct InFlightLoad {
        let id: UUID
        let task: Task<[CachedVideoDTO], Error>
    }

    private var memoryCache: [StreamListCacheKey: StreamListCacheEntry] = [:]
    private var inFlightTasks: [StreamListCacheKey: InFlightLoad] = [:]

    private let store: any StreamListCachePersisting
    private let now: @Sendable () -> Date

    init(
        store: any StreamListCachePersisting,
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

    func pruneCacheIfNeeded() async throws {
        try await store.pruneCacheIfNeeded()
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

        guard let storedEntry = try await store.load(key: key) else { return nil }
        memoryCache[key] = storedEntry
        return CatalogCachedValue(
            value: storedEntry.videos,
            savedAt: storedEntry.savedAt
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
        try await store.entries(providerFingerprint: providerFingerprint)
    }

    func entry(for key: StreamListCacheKey) async throws -> StreamListCacheEntry? {
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

    func removeValue(for key: StreamListCacheKey) async throws {
        inFlightTasks[key]?.task.cancel()
        inFlightTasks[key] = nil
        memoryCache[key] = nil
        try await store.removeValue(for: key)
    }

    func removeAll(for providerFingerprint: String) async throws {
        memoryCache = memoryCache.filter { $0.key.providerFingerprint != providerFingerprint }
        try await store.removeAll(for: providerFingerprint)
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
        try? await store.save(entry, for: key)
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
