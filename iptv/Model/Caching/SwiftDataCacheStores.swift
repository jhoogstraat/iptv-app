//
//  SwiftDataCacheStores.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import Foundation
import SwiftData

actor SwiftDataStreamListCacheStore: StreamListCacheStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func load(key: StreamListCacheKey) async throws -> StreamListCacheEntry? {
        let context = ModelContext(modelContainer)
        let providerFingerprint = key.providerFingerprint
        let contentType = key.contentType.rawValue
        let categoryID = key.categoryID
        let pageToken = key.pageToken
        let records = try context.fetch(
            FetchDescriptor<PersistedStreamRecord>(
                predicate: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.contentType == contentType &&
                    $0.categoryID == categoryID &&
                    $0.pageToken == pageToken
                },
                sortBy: [SortDescriptor(\.sortIndex, order: .forward)]
            )
        )

        guard let first = records.first else { return nil }
        let touchedAt = Date()
        for record in records {
            record.lastAccessAt = touchedAt
        }
        try context.save()

        return StreamListCacheEntry(
            key: key,
            savedAt: first.savedAt,
            lastAccessAt: touchedAt,
            videos: records.map { record in
                CachedVideoDTO(
                    id: record.videoID,
                    name: record.name,
                    containerExtension: record.containerExtension,
                    contentType: record.playbackContentType,
                    coverImageURL: record.coverImageURL,
                    tmdbId: record.tmdbId,
                    rating: record.rating,
                    added: record.addedAtRaw
                )
            }
        )
    }

    func save(_ entry: StreamListCacheEntry, for key: StreamListCacheKey) async throws {
        let context = ModelContext(modelContainer)
        let providerFingerprint = key.providerFingerprint
        let contentType = key.contentType.rawValue
        let categoryID = key.categoryID
        let pageToken = key.pageToken
        let existing = try context.fetch(
            FetchDescriptor<PersistedStreamRecord>(
                predicate: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.contentType == contentType &&
                    $0.categoryID == categoryID &&
                    $0.pageToken == pageToken
                }
            )
        )
        for record in existing {
            context.delete(record)
        }

        for (index, video) in entry.videos.enumerated() {
            context.insert(
                PersistedStreamRecord(
                    id: Self.recordID(for: key, videoID: video.id),
                    providerFingerprint: key.providerFingerprint,
                    contentType: key.contentType.rawValue,
                    categoryID: key.categoryID,
                    pageToken: key.pageToken,
                    videoID: video.id,
                    sortIndex: index,
                    name: video.name,
                    containerExtension: video.containerExtension,
                    playbackContentType: video.contentType,
                    coverImageURL: video.coverImageURL,
                    tmdbId: video.tmdbId,
                    rating: video.rating,
                    addedAtRaw: video.added,
                    savedAt: entry.savedAt,
                    lastAccessAt: entry.lastAccessAt
                )
            )
        }

        try context.save()
    }

    func entries(providerFingerprint: String) async throws -> [StreamListCacheEntry] {
        let context = ModelContext(modelContainer)
        let records = try context.fetch(
            FetchDescriptor<PersistedStreamRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint },
                sortBy: [
                    SortDescriptor(\.contentType, order: .forward),
                    SortDescriptor(\.categoryID, order: .forward),
                    SortDescriptor(\.pageToken, order: .forward),
                    SortDescriptor(\.sortIndex, order: .forward)
                ]
            )
        )

        let grouped = Dictionary(grouping: records) {
            StreamListCacheKey(
                providerFingerprint: $0.providerFingerprint,
                contentType: XtreamContentType(rawValue: $0.contentType) ?? .vod,
                categoryID: $0.categoryID,
                pageToken: $0.pageToken
            )
        }

        return grouped.map { key, group in
            let first = group[0]
            return StreamListCacheEntry(
                key: key,
                savedAt: first.savedAt,
                lastAccessAt: first.lastAccessAt,
                videos: group
                    .sorted { $0.sortIndex < $1.sortIndex }
                    .map { record in
                        CachedVideoDTO(
                            id: record.videoID,
                            name: record.name,
                            containerExtension: record.containerExtension,
                            contentType: record.playbackContentType,
                            coverImageURL: record.coverImageURL,
                            tmdbId: record.tmdbId,
                            rating: record.rating,
                            added: record.addedAtRaw
                        )
                    }
            )
        }
    }

    func pruneCacheIfNeeded() async throws { }

    func removeValue(for key: StreamListCacheKey) async throws {
        let context = ModelContext(modelContainer)
        let providerFingerprint = key.providerFingerprint
        let contentType = key.contentType.rawValue
        let categoryID = key.categoryID
        let pageToken = key.pageToken
        let records = try context.fetch(
            FetchDescriptor<PersistedStreamRecord>(
                predicate: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.contentType == contentType &&
                    $0.categoryID == categoryID &&
                    $0.pageToken == pageToken
                }
            )
        )
        for record in records {
            context.delete(record)
        }
        try context.save()
    }

    func removeAll(for providerFingerprint: String) async throws {
        let context = ModelContext(modelContainer)
        let records = try context.fetch(
            FetchDescriptor<PersistedStreamRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )
        for record in records {
            context.delete(record)
        }
        try context.save()
    }

    private static func recordID(for key: StreamListCacheKey, videoID: Int) -> String {
        "\(key.rawKey)|\(videoID)"
    }
}

actor SwiftDataCatalogMetadataCacheStore: CatalogMetadataCacheStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func load(key: CatalogMetadataCacheKey) async throws -> CatalogMetadataCacheEntry? {
        let context = ModelContext(modelContainer)
        let currentDate = Date()

        switch key.kind {
        case .vodCategories, .seriesCategories:
            let contentType = Self.categoryContentType(for: key.kind)
            let providerFingerprint = key.providerFingerprint
            let categories = try context.fetch(
                FetchDescriptor<PersistedCategoryRecord>(
                    predicate: #Predicate {
                        $0.providerFingerprint == providerFingerprint &&
                        $0.contentType == contentType
                    },
                    sortBy: [SortDescriptor(\.sortIndex, order: .forward)]
                )
            )
            guard let first = categories.first else { return nil }
            let dto = categories.map { CachedCategoryDTO(id: $0.categoryID, name: $0.name) }
            let payload = try JSONEncoder().encode(dto)
            return CatalogMetadataCacheEntry(
                key: key,
                savedAt: first.updatedAt,
                lastAccessAt: currentDate,
                payload: payload
            )
        case .vodInfo:
            guard let record = try fetchMovieDetail(for: key, context: context) else { return nil }
            record.lastAccessAt = currentDate
            try context.save()
            let dto = CachedVideoInfoDTO(
                images: record.imageURLs.compactMap(URL.init(string:)),
                plot: record.plot,
                cast: record.cast,
                director: record.director,
                genre: record.genre,
                releaseDate: record.releaseDate,
                durationLabel: record.durationLabel,
                runtimeMinutes: record.runtimeMinutes,
                ageRating: record.ageRating,
                country: record.country,
                rating: record.rating,
                streamBitrate: record.streamBitrate,
                audioDescription: record.audioDescription,
                videoResolution: record.videoResolution,
                videoFrameRate: record.videoFrameRate
            )
            return CatalogMetadataCacheEntry(
                key: key,
                savedAt: record.savedAt,
                lastAccessAt: currentDate,
                payload: try JSONEncoder().encode(dto)
            )
        case .seriesInfo:
            guard let record = try fetchSeriesDetail(for: key, context: context) else { return nil }
            record.lastAccessAt = currentDate
            try context.save()
            return CatalogMetadataCacheEntry(
                key: key,
                savedAt: record.savedAt,
                lastAccessAt: currentDate,
                payload: record.payload
            )
        }
    }

    func save(_ entry: CatalogMetadataCacheEntry, for key: CatalogMetadataCacheKey) async throws {
        let context = ModelContext(modelContainer)

        switch key.kind {
        case .vodCategories, .seriesCategories:
            let providerFingerprint = key.providerFingerprint
            let contentType = Self.categoryContentType(for: key.kind)
            let existing = try context.fetch(
                FetchDescriptor<PersistedCategoryRecord>(
                    predicate: #Predicate {
                        $0.providerFingerprint == providerFingerprint &&
                        $0.contentType == contentType
                    }
                )
            )
            for record in existing {
                context.delete(record)
            }

            let categories = try JSONDecoder().decode([CachedCategoryDTO].self, from: entry.payload)
            for (index, category) in categories.enumerated() {
                context.insert(
                    PersistedCategoryRecord(
                        id: Self.categoryRecordID(
                            providerFingerprint: providerFingerprint,
                            contentType: contentType,
                            categoryID: category.id
                        ),
                        providerFingerprint: providerFingerprint,
                        contentType: contentType,
                        categoryID: category.id,
                        name: category.name,
                        sortIndex: index,
                        updatedAt: entry.savedAt
                    )
                )
            }
        case .vodInfo:
            let dto = try JSONDecoder().decode(CachedVideoInfoDTO.self, from: entry.payload)
            if let existing = try fetchMovieDetail(for: key, context: context) {
                context.delete(existing)
            }
            context.insert(
                PersistedMovieDetailRecord(
                    id: key.rawKey,
                    providerFingerprint: key.providerFingerprint,
                    videoID: Int(key.resourceID) ?? 0,
                    imageURLs: dto.images.map(\.absoluteString),
                    plot: dto.plot,
                    cast: dto.cast,
                    director: dto.director,
                    genre: dto.genre,
                    releaseDate: dto.releaseDate,
                    durationLabel: dto.durationLabel,
                    runtimeMinutes: dto.runtimeMinutes,
                    ageRating: dto.ageRating,
                    country: dto.country,
                    rating: dto.rating,
                    streamBitrate: dto.streamBitrate,
                    audioDescription: dto.audioDescription,
                    videoResolution: dto.videoResolution,
                    videoFrameRate: dto.videoFrameRate,
                    savedAt: entry.savedAt,
                    lastAccessAt: entry.lastAccessAt
                )
            )
        case .seriesInfo:
            if let existing = try fetchSeriesDetail(for: key, context: context) {
                context.delete(existing)
            }
            context.insert(
                PersistedSeriesDetailRecord(
                    id: key.rawKey,
                    providerFingerprint: key.providerFingerprint,
                    seriesID: Int(key.resourceID) ?? 0,
                    payload: entry.payload,
                    savedAt: entry.savedAt,
                    lastAccessAt: entry.lastAccessAt
                )
            )
        }

        try context.save()
    }

    func entries(providerFingerprint: String) async throws -> [CatalogMetadataCacheEntry] {
        let context = ModelContext(modelContainer)
        var results: [CatalogMetadataCacheEntry] = []
        let vodContentType = XtreamContentType.vod.rawValue
        let seriesContentType = XtreamContentType.series.rawValue

        let vodCategories = try context.fetch(
            FetchDescriptor<PersistedCategoryRecord>(
                predicate: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.contentType == vodContentType
                },
                sortBy: [SortDescriptor(\.sortIndex, order: .forward)]
            )
        )
        if let first = vodCategories.first {
            let payload = try JSONEncoder().encode(vodCategories.map { CachedCategoryDTO(id: $0.categoryID, name: $0.name) })
            results.append(
                CatalogMetadataCacheEntry(
                    key: CatalogMetadataCacheKey(providerFingerprint: providerFingerprint, kind: .vodCategories, resourceID: "all"),
                    savedAt: first.updatedAt,
                    lastAccessAt: first.updatedAt,
                    payload: payload
                )
            )
        }

        let seriesCategories = try context.fetch(
            FetchDescriptor<PersistedCategoryRecord>(
                predicate: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.contentType == seriesContentType
                },
                sortBy: [SortDescriptor(\.sortIndex, order: .forward)]
            )
        )
        if let first = seriesCategories.first {
            let payload = try JSONEncoder().encode(seriesCategories.map { CachedCategoryDTO(id: $0.categoryID, name: $0.name) })
            results.append(
                CatalogMetadataCacheEntry(
                    key: CatalogMetadataCacheKey(providerFingerprint: providerFingerprint, kind: .seriesCategories, resourceID: "all"),
                    savedAt: first.updatedAt,
                    lastAccessAt: first.updatedAt,
                    payload: payload
                )
            )
        }

        let movieDetails = try context.fetch(
            FetchDescriptor<PersistedMovieDetailRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )
        results.append(contentsOf: try movieDetails.map { record in
            let dto = CachedVideoInfoDTO(
                images: record.imageURLs.compactMap(URL.init(string:)),
                plot: record.plot,
                cast: record.cast,
                director: record.director,
                genre: record.genre,
                releaseDate: record.releaseDate,
                durationLabel: record.durationLabel,
                runtimeMinutes: record.runtimeMinutes,
                ageRating: record.ageRating,
                country: record.country,
                rating: record.rating,
                streamBitrate: record.streamBitrate,
                audioDescription: record.audioDescription,
                videoResolution: record.videoResolution,
                videoFrameRate: record.videoFrameRate
            )
            return CatalogMetadataCacheEntry(
                key: CatalogMetadataCacheKey(
                    providerFingerprint: providerFingerprint,
                    kind: .vodInfo,
                    resourceID: String(record.videoID)
                ),
                savedAt: record.savedAt,
                lastAccessAt: record.lastAccessAt,
                payload: try JSONEncoder().encode(dto)
            )
        })

        let seriesDetails = try context.fetch(
            FetchDescriptor<PersistedSeriesDetailRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )
        results.append(contentsOf: seriesDetails.map { record in
            CatalogMetadataCacheEntry(
                key: CatalogMetadataCacheKey(
                    providerFingerprint: providerFingerprint,
                    kind: .seriesInfo,
                    resourceID: String(record.seriesID)
                ),
                savedAt: record.savedAt,
                lastAccessAt: record.lastAccessAt,
                payload: record.payload
            )
        })

        return results
    }

    func removeValue(for key: CatalogMetadataCacheKey) async throws {
        let context = ModelContext(modelContainer)

        switch key.kind {
        case .vodCategories, .seriesCategories:
            let providerFingerprint = key.providerFingerprint
            let contentType = Self.categoryContentType(for: key.kind)
            let records = try context.fetch(
                FetchDescriptor<PersistedCategoryRecord>(
                    predicate: #Predicate {
                        $0.providerFingerprint == providerFingerprint &&
                        $0.contentType == contentType
                    }
                )
            )
            for record in records {
                context.delete(record)
            }
        case .vodInfo:
            if let record = try fetchMovieDetail(for: key, context: context) {
                context.delete(record)
            }
        case .seriesInfo:
            if let record = try fetchSeriesDetail(for: key, context: context) {
                context.delete(record)
            }
        }

        try context.save()
    }

    func removeAll(for providerFingerprint: String) async throws {
        let context = ModelContext(modelContainer)

        for category in try context.fetch(
            FetchDescriptor<PersistedCategoryRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        ) {
            context.delete(category)
        }

        for detail in try context.fetch(
            FetchDescriptor<PersistedMovieDetailRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        ) {
            context.delete(detail)
        }

        for detail in try context.fetch(
            FetchDescriptor<PersistedSeriesDetailRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        ) {
            context.delete(detail)
        }

        try context.save()
    }

    func pruneCacheIfNeeded() async throws { }

    private static func categoryContentType(for kind: CatalogMetadataKind) -> String {
        switch kind {
        case .vodCategories:
            XtreamContentType.vod.rawValue
        case .seriesCategories:
            XtreamContentType.series.rawValue
        case .vodInfo, .seriesInfo:
            ""
        }
    }

    private static func categoryRecordID(
        providerFingerprint: String,
        contentType: String,
        categoryID: String
    ) -> String {
        "\(providerFingerprint)|\(contentType)|\(categoryID)"
    }

    private func fetchMovieDetail(
        for key: CatalogMetadataCacheKey,
        context: ModelContext
    ) throws -> PersistedMovieDetailRecord? {
        let providerFingerprint = key.providerFingerprint
        let videoID = Int(key.resourceID) ?? 0
        let records = try context.fetch(
            FetchDescriptor<PersistedMovieDetailRecord>(
                predicate: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.videoID == videoID
                }
            )
        )
        return records.first
    }

    private func fetchSeriesDetail(
        for key: CatalogMetadataCacheKey,
        context: ModelContext
    ) throws -> PersistedSeriesDetailRecord? {
        let providerFingerprint = key.providerFingerprint
        let seriesID = Int(key.resourceID) ?? 0
        let records = try context.fetch(
            FetchDescriptor<PersistedSeriesDetailRecord>(
                predicate: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.seriesID == seriesID
                }
            )
        )
        return records.first
    }
}
