//
//  FavoritesStore.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import Foundation
import Observation
import OSLog

nonisolated struct FavoriteInput: Hashable, Sendable {
    let videoID: Int
    let contentType: String
    let title: String
    let coverImageURL: String?
    let containerExtension: String
    let rating: Double?
}

nonisolated struct FavoriteRecord: Codable, Hashable, Sendable, Identifiable {
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

    nonisolated static func makeKey(providerFingerprint: String, contentType: String, videoID: Int) -> String {
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

@MainActor
@Observable
final class FavoritesStore {
    private let store: FavoritesPersistence
    private(set) var revision = 0

    init(store: FavoritesPersistence) {
        self.store = store
    }

    func load(providerFingerprint: String) async -> [FavoriteRecord] {
        do {
            return try await store.records(for: providerFingerprint)
        } catch {
            logger.error("Failed to load favorites: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func contains(video: Video, providerFingerprint: String) async -> Bool {
        do {
            return try await store.contains(
                providerFingerprint: providerFingerprint,
                contentType: video.contentType,
                videoID: video.id
            )
        } catch {
            logger.error("Failed to check favorite status: \(error.localizedDescription, privacy: .public)")
            return false
        }
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

        do {
            if isFavorite {
                try await store.add(input: input, providerFingerprint: providerFingerprint)
            } else {
                try await store.remove(input: input, providerFingerprint: providerFingerprint)
            }
            revision += 1
        } catch {
            logger.error("Failed to update favorite state: \(error.localizedDescription, privacy: .public)")
        }
    }
}
