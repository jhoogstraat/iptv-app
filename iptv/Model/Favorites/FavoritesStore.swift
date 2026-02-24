//
//  FavoritesStore.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import Foundation
import Observation
import OSLog

struct FavoriteInput: Hashable, Sendable {
    let videoID: Int
    let contentType: String
    let title: String
    let coverImageURL: String?
    let containerExtension: String
    let rating: Double?
}

struct FavoriteRecord: Codable, Hashable, Sendable, Identifiable {
    let providerFingerprint: String
    let videoID: Int
    let contentType: String
    let title: String
    let coverImageURL: String?
    let containerExtension: String
    let rating: Double?
    let createdAt: Date

    var id: String {
        Self.makeKey(providerFingerprint: providerFingerprint, contentType: contentType, videoID: videoID)
    }

    static func makeKey(providerFingerprint: String, contentType: String, videoID: Int) -> String {
        "\(providerFingerprint)|\(contentType)|\(videoID)"
    }

    static func from(input: FavoriteInput, providerFingerprint: String, createdAt: Date) -> FavoriteRecord {
        FavoriteRecord(
            providerFingerprint: providerFingerprint,
            videoID: input.videoID,
            contentType: input.contentType,
            title: input.title,
            coverImageURL: input.coverImageURL,
            containerExtension: input.containerExtension,
            rating: input.rating,
            createdAt: createdAt
        )
    }

    func asVideo() -> Video {
        Video(
            id: videoID,
            name: title,
            containerExtension: containerExtension,
            contentType: contentType,
            coverImageURL: coverImageURL,
            tmdbId: nil,
            rating: rating
        )
    }
}

protocol FavoriteStoring: Sendable {
    func loadAll() async -> [FavoriteRecord]
    func add(input: FavoriteInput, providerFingerprint: String) async
    func remove(input: FavoriteInput, providerFingerprint: String) async
    func clear(for providerFingerprint: String) async
}

actor DiskFavoritesStore: FavoriteStoring {
    static let shared = DiskFavoritesStore()

    private let fileURL: URL
    private let now: @Sendable () -> Date
    private var didLoad = false
    private var recordsByKey: [String: FavoriteRecord] = [:]

    init(
        fileURL: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let defaultURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(path: "Favorites", directoryHint: .isDirectory)
            .appending(path: "favorites.json")
        self.fileURL = fileURL ?? defaultURL
        self.now = now
    }

    func loadAll() async -> [FavoriteRecord] {
        await ensureLoaded()
        return recordsByKey.values.sorted { $0.createdAt > $1.createdAt }
    }

    func add(input: FavoriteInput, providerFingerprint: String) async {
        await ensureLoaded()
        let key = FavoriteRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: input.contentType,
            videoID: input.videoID
        )
        recordsByKey[key] = FavoriteRecord.from(input: input, providerFingerprint: providerFingerprint, createdAt: now())
        await persist()
    }

    func remove(input: FavoriteInput, providerFingerprint: String) async {
        await ensureLoaded()
        let key = FavoriteRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: input.contentType,
            videoID: input.videoID
        )
        recordsByKey[key] = nil
        await persist()
    }

    func clear(for providerFingerprint: String) async {
        await ensureLoaded()
        recordsByKey = recordsByKey.filter { $0.value.providerFingerprint != providerFingerprint }
        await persist()
    }

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directoryURL.path()) {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }

            guard FileManager.default.fileExists(atPath: fileURL.path()) else {
                recordsByKey = [:]
                return
            }

            let data = try Data(contentsOf: fileURL)
            let records = try JSONDecoder().decode([FavoriteRecord].self, from: data)
            recordsByKey = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        } catch {
            recordsByKey = [:]
            logger.error("Favorites load failed, resetting file: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persist() async {
        do {
            let records = recordsByKey.values.sorted { $0.createdAt > $1.createdAt }
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            logger.error("Favorites persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
@Observable
final class FavoritesStore {
    private let store: any FavoriteStoring
    private(set) var revision = 0

    init(store: any FavoriteStoring = DiskFavoritesStore.shared) {
        self.store = store
    }

    func load(providerFingerprint: String) async -> [FavoriteRecord] {
        await store.loadAll().filter { $0.providerFingerprint == providerFingerprint }
    }

    func contains(video: Video, providerFingerprint: String) async -> Bool {
        let key = FavoriteRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: video.contentType,
            videoID: video.id
        )
        return await store.loadAll().contains { $0.id == key }
    }

    func setFavorite(video: Video, providerFingerprint: String, isFavorite: Bool) async {
        let input = FavoriteInput(
            videoID: video.id,
            contentType: video.contentType,
            title: video.name,
            coverImageURL: video.coverImageURL,
            containerExtension: video.containerExtension,
            rating: video.rating
        )

        if isFavorite {
            await store.add(input: input, providerFingerprint: providerFingerprint)
        } else {
            await store.remove(input: input, providerFingerprint: providerFingerprint)
        }
        revision += 1
    }
}

