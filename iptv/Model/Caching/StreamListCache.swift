//
//  StreamListCache.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation
import CryptoKit

struct StreamListCacheKey: Codable, Hashable, Sendable {
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

struct CachedVideoDTO: Codable, Hashable, Sendable {
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

struct StreamListCacheEntry: Codable, Sendable {
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

protocol StreamListCacheStore: Sendable {
    func load(key: StreamListCacheKey) async throws -> StreamListCacheEntry?
    func save(_ entry: StreamListCacheEntry, for key: StreamListCacheKey) async throws
    func pruneCacheIfNeeded() async throws
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
        let baseDirectory = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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

    func removeAll(for providerFingerprint: String) async throws {
        try ensureDirectoryExists()

        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let decoder = JSONDecoder()
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let entry = try? decoder.decode(StreamListCacheEntry.self, from: data),
                  entry.key.providerFingerprint == providerFingerprint else {
                continue
            }
            try? fileManager.removeItem(at: file)
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
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    init(
        diskStore: StreamListCacheStore = DiskStreamListCacheStore(),
        ttl: TimeInterval = 15 * 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.diskStore = diskStore
        self.ttl = ttl
        self.now = now

        Task(priority: .utility) {
            try? await diskStore.pruneCacheIfNeeded()
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

    func loadStreamList(
        for key: StreamListCacheKey,
        force: Bool = false,
        fetcher: @escaping @Sendable () async throws -> [CachedVideoDTO]
    ) async throws -> [CachedVideoDTO] {
        let currentDate = now()
        var staleFallback: StreamListCacheEntry?

        if !force {
            if let memoryEntry = memoryCache[key] {
                let touched = memoryEntry.touching(at: currentDate)
                memoryCache[key] = touched
                if !isStale(memoryEntry.savedAt, at: currentDate) {
                    return touched.videos
                }
                staleFallback = touched
            }

            if staleFallback == nil, let diskEntry = try await diskStore.load(key: key) {
                let touched = diskEntry.touching(at: currentDate)
                memoryCache[key] = touched
                if !isStale(diskEntry.savedAt, at: currentDate) {
                    return touched.videos
                }
                staleFallback = touched
            }
        }

        if let inFlight = inFlightTasks[key] {
            do {
                return try await inFlight.task.value
            } catch {
                if let staleFallback, !force {
                    return staleFallback.videos
                }
                throw error
            }
        }

        let inFlight = startFetch(for: key, fetcher: fetcher)

        do {
            return try await inFlight.task.value
        } catch {
            if let staleFallback, !force {
                return staleFallback.videos
            }
            throw error
        }
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

    private func isStale(_ savedAt: Date, at currentDate: Date) -> Bool {
        currentDate.timeIntervalSince(savedAt) > ttl
    }
}

protocol ImagePrefetching: Sendable {
    func prefetch(urls: [URL]) async
}

struct NoopImagePrefetcher: ImagePrefetching {
    func prefetch(urls: [URL]) async { }
}

enum ProviderCacheFingerprint {
    static func make(from config: ProviderConfig) -> String {
        "\(config.apiURL.absoluteString)|\(config.username)".sha256Hex
    }
}

private extension String {
    var sha256Hex: String {
        let digest = SHA256.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
