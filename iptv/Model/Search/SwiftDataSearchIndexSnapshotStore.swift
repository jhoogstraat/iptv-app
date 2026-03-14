//
//  SwiftDataSearchIndexSnapshotStore.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import Foundation
import SwiftData

actor SwiftDataSearchIndexSnapshotStore: SearchIndexSnapshotStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func load(providerFingerprint: String) async throws -> SearchIndexStore.ProviderIndex? {
        let context = ModelContext(modelContainer)
        let documents = try context.fetch(
            FetchDescriptor<PersistedSearchDocumentRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )
        let indexedCategories = try context.fetch(
            FetchDescriptor<PersistedSearchIndexedCategoryRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )

        guard !documents.isEmpty || !indexedCategories.isEmpty else { return nil }

        var index = SearchIndexStore.ProviderIndex()
        for record in documents {
            let pairs = Array(zip(record.categoryIDs, record.categories))
            let normalizedPairs = Array(zip(record.categoryIDs, record.normalizedCategories))
            let document = SearchIndexStore.SearchDocument(
                key: record.id,
                videoID: record.videoID,
                indexedContentType: XtreamContentType(rawValue: record.indexedContentType) ?? .vod,
                playbackContentType: record.playbackContentType,
                title: record.title,
                normalizedTitle: record.normalizedTitle,
                containerExtension: record.containerExtension,
                coverImageURL: record.coverImageURL,
                rating: record.rating,
                addedAtRaw: record.addedAtRaw,
                addedAt: record.addedAt,
                language: record.language,
                normalizedLanguage: record.normalizedLanguage,
                categoryNamesByID: Dictionary(uniqueKeysWithValues: pairs),
                normalizedCategoryNamesByID: Dictionary(uniqueKeysWithValues: normalizedPairs)
            )
            index.documentsByKey[document.key] = document
            index.insertKey(document.key, for: document.indexedContentType)
        }

        for record in indexedCategories {
            index.markCategoryIndexed(
                record.categoryID,
                for: XtreamContentType(rawValue: record.contentType) ?? .vod
            )
        }

        return index
    }

    func save(_ index: SearchIndexStore.ProviderIndex, providerFingerprint: String) async throws {
        let context = ModelContext(modelContainer)
        try deleteAll(providerFingerprint: providerFingerprint, context: context)

        for document in index.documentsByKey.values {
            let sortedCategoryIDs = document.categoryNamesByID.keys.sorted()
            context.insert(
                PersistedSearchDocumentRecord(
                    id: document.key,
                    providerFingerprint: providerFingerprint,
                    videoID: document.videoID,
                    indexedContentType: document.indexedContentType.rawValue,
                    playbackContentType: document.playbackContentType,
                    title: document.title,
                    normalizedTitle: document.normalizedTitle,
                    containerExtension: document.containerExtension,
                    coverImageURL: document.coverImageURL,
                    rating: document.rating,
                    addedAtRaw: document.addedAtRaw,
                    addedAt: document.addedAt,
                    language: document.language,
                    normalizedLanguage: document.normalizedLanguage,
                    categoryIDs: sortedCategoryIDs,
                    categories: sortedCategoryIDs.map { document.categoryNamesByID[$0] ?? "" },
                    normalizedCategories: sortedCategoryIDs.map { document.normalizedCategoryNamesByID[$0] ?? "" },
                    genres: Array(document.genres).sorted(),
                    normalizedGenres: Array(document.normalizedGenres).sorted()
                )
            )
        }

        for categoryID in index.indexedMovieCategoryIDs {
            context.insert(
                PersistedSearchIndexedCategoryRecord(
                    id: "\(providerFingerprint)|\(XtreamContentType.vod.rawValue)|\(categoryID)",
                    providerFingerprint: providerFingerprint,
                    contentType: XtreamContentType.vod.rawValue,
                    categoryID: categoryID
                )
            )
        }

        for categoryID in index.indexedSeriesCategoryIDs {
            context.insert(
                PersistedSearchIndexedCategoryRecord(
                    id: "\(providerFingerprint)|\(XtreamContentType.series.rawValue)|\(categoryID)",
                    providerFingerprint: providerFingerprint,
                    contentType: XtreamContentType.series.rawValue,
                    categoryID: categoryID
                )
            )
        }

        try context.save()
    }

    func remove(providerFingerprint: String) async throws {
        let context = ModelContext(modelContainer)
        try deleteAll(providerFingerprint: providerFingerprint, context: context)
        try context.save()
    }

    func removeAll() async throws {
        let context = ModelContext(modelContainer)
        for document in try context.fetch(FetchDescriptor<PersistedSearchDocumentRecord>()) {
            context.delete(document)
        }
        for category in try context.fetch(FetchDescriptor<PersistedSearchIndexedCategoryRecord>()) {
            context.delete(category)
        }
        try context.save()
    }

    private func deleteAll(providerFingerprint: String, context: ModelContext) throws {
        for document in try context.fetch(
            FetchDescriptor<PersistedSearchDocumentRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        ) {
            context.delete(document)
        }
        for category in try context.fetch(
            FetchDescriptor<PersistedSearchIndexedCategoryRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        ) {
            context.delete(category)
        }
    }
}
