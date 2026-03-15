//
//  FavoritesPersistence.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import Foundation
import SwiftData

@ModelActor
actor FavoritesPersistence {
    private var now: @Sendable () -> Date = Date.init

    init(
        modelContainer: ModelContainer,
        now: @escaping @Sendable () -> Date
    ) {
        let modelContext = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
        self.now = now
    }

    func records(for providerFingerprint: String) throws -> [FavoriteRecord] {
        let descriptor = FetchDescriptor<PersistedFavoriteStoreRecord>(
            predicate: #Predicate { $0.providerFingerprint == providerFingerprint },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = try modelContext.fetch(descriptor)
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

    func contains(providerFingerprint: String, contentType: String, videoID: Int) throws -> Bool {
        let id = FavoriteRecord.makeKey(providerFingerprint: providerFingerprint, contentType: contentType, videoID: videoID)
        let descriptor = FetchDescriptor<PersistedFavoriteStoreRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetchCount(descriptor) > 0
    }

    func add(input: FavoriteInput, providerFingerprint: String) throws {
        let id = FavoriteRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: input.contentType,
            videoID: input.videoID
        )

        modelContext.insert(
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
        try modelContext.save()
    }

    func remove(input: FavoriteInput, providerFingerprint: String) throws {
        let id = FavoriteRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: input.contentType,
            videoID: input.videoID
        )
        try modelContext.delete(
            model: PersistedFavoriteStoreRecord.self,
            where: #Predicate { $0.id == id }
        )
        try modelContext.save()
    }

    func clear(for providerFingerprint: String) throws {
        try modelContext.delete(
            model: PersistedFavoriteStoreRecord.self,
            where: #Predicate { $0.providerFingerprint == providerFingerprint }
        )
        try modelContext.save()
    }
}
