//
//  SwiftDataFavoritesStore.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import Foundation
import SwiftData

actor SwiftDataFavoritesStore: FavoriteStoring {
    private let modelContainer: ModelContainer
    private let now: @Sendable () -> Date

    init(
        modelContainer: ModelContainer,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.modelContainer = modelContainer
        self.now = now
    }

    func loadAll() async -> [FavoriteRecord] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistedFavoriteStoreRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map {
            FavoriteRecord(
                providerFingerprint: $0.providerFingerprint,
                videoID: $0.videoID,
                contentType: $0.contentType,
                title: $0.title,
                coverImageURL: $0.coverImageURL,
                containerExtension: $0.containerExtension,
                rating: $0.rating,
                createdAt: $0.createdAt
            )
        }
    }

    func contains(providerFingerprint: String, contentType: String, videoID: Int) async -> Bool {
        let context = ModelContext(modelContainer)
        let id = FavoriteRecord.makeKey(providerFingerprint: providerFingerprint, contentType: contentType, videoID: videoID)
        let records = (try? context.fetch(
            FetchDescriptor<PersistedFavoriteStoreRecord>(
                predicate: #Predicate { $0.id == id }
            )
        )) ?? []
        return !records.isEmpty
    }

    func add(input: FavoriteInput, providerFingerprint: String) async {
        let context = ModelContext(modelContainer)
        let id = FavoriteRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: input.contentType,
            videoID: input.videoID
        )
        if let existing = ((try? context.fetch(
            FetchDescriptor<PersistedFavoriteStoreRecord>(predicate: #Predicate { $0.id == id })
        )) ?? []).first {
            context.delete(existing)
        }

        context.insert(
            PersistedFavoriteStoreRecord(
                id: id,
                providerFingerprint: providerFingerprint,
                videoID: input.videoID,
                contentType: input.contentType,
                title: input.title,
                coverImageURL: input.coverImageURL,
                containerExtension: input.containerExtension,
                rating: input.rating,
                createdAt: now()
            )
        )
        try? context.save()
    }

    func remove(input: FavoriteInput, providerFingerprint: String) async {
        let context = ModelContext(modelContainer)
        let id = FavoriteRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: input.contentType,
            videoID: input.videoID
        )
        let matches = (try? context.fetch(
            FetchDescriptor<PersistedFavoriteStoreRecord>(predicate: #Predicate { $0.id == id })
        )) ?? []
        for match in matches {
            context.delete(match)
        }
        try? context.save()
    }

    func clear(for providerFingerprint: String) async {
        let context = ModelContext(modelContainer)
        let matches = (try? context.fetch(
            FetchDescriptor<PersistedFavoriteStoreRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )) ?? []
        for match in matches {
            context.delete(match)
        }
        try? context.save()
    }
}
