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

        return StreamListCacheEntry(
            key: key,
            savedAt: first.savedAt,
            lastAccessAt: first.lastAccessAt,
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
        let categoryRecord = try fetchCategoryRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID,
            context: context
        )
        let categoryName = categoryRecord?.name ?? categoryID
        let normalizedCategoryName = Self.normalize(categoryName)
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
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var retainedRecordIDs = Set<String>()

        for (index, video) in entry.videos.enumerated() {
            let recordID = Self.recordID(for: key, videoID: video.id)
            retainedRecordIDs.insert(recordID)

            let language = Self.languageCode(from: video.name)
            if let record = existingByID[recordID] {
                record.providerFingerprint = key.providerFingerprint
                record.contentType = key.contentType.rawValue
                record.categoryID = key.categoryID
                record.categoryName = categoryName
                record.normalizedCategoryName = normalizedCategoryName
                record.pageToken = key.pageToken
                record.videoID = video.id
                record.sortIndex = index
                record.name = video.name
                record.normalizedTitle = Self.normalize(video.name)
                record.language = language
                record.normalizedLanguage = language.map(Self.normalize)
                record.containerExtension = video.containerExtension
                record.playbackContentType = video.contentType
                record.coverImageURL = video.coverImageURL
                record.tmdbId = video.tmdbId
                record.rating = video.rating
                record.addedAtRaw = video.added
                record.addedAt = Self.parseDate(video.added)
                record.savedAt = entry.savedAt
                record.lastAccessAt = entry.lastAccessAt
            } else {
                context.insert(
                    PersistedStreamRecord(
                        id: recordID,
                        providerFingerprint: key.providerFingerprint,
                        contentType: key.contentType.rawValue,
                        categoryID: key.categoryID,
                        categoryName: categoryName,
                        normalizedCategoryName: normalizedCategoryName,
                        pageToken: key.pageToken,
                        videoID: video.id,
                        sortIndex: index,
                        name: video.name,
                        normalizedTitle: Self.normalize(video.name),
                        language: language,
                        normalizedLanguage: language.map(Self.normalize),
                        containerExtension: video.containerExtension,
                        playbackContentType: video.contentType,
                        coverImageURL: video.coverImageURL,
                        tmdbId: video.tmdbId,
                        rating: video.rating,
                        addedAtRaw: video.added,
                        addedAt: Self.parseDate(video.added),
                        savedAt: entry.savedAt,
                        lastAccessAt: entry.lastAccessAt
                    )
                )
            }
        }

        for record in existing where !retainedRecordIDs.contains(record.id) {
            context.delete(record)
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

    private func fetchCategoryRecord(
        providerFingerprint: String,
        contentType: String,
        categoryID: String,
        context: ModelContext
    ) throws -> PersistedCategoryRecord? {
        try context.fetch(
            FetchDescriptor<PersistedCategoryRecord>(
                predicate: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.contentType == contentType &&
                    $0.categoryID == categoryID
                }
            )
        ).first
    }

    private static func normalize(_ input: String) -> String {
        input
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func languageCode(from title: String) -> String? {
        LanguageTaggedText(title).languageCode
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let seconds = Double(value), value.allSatisfy(\.isNumber) {
            return Date(timeIntervalSince1970: seconds)
        }

        let formats = [
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy/MM/dd",
            "dd-MM-yyyy",
            "MM/dd/yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
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
            let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            let categories = try JSONDecoder().decode([CachedCategoryDTO].self, from: entry.payload)
            var retainedRecordIDs = Set<String>()
            for (index, category) in categories.enumerated() {
                let recordID = Self.categoryRecordID(
                    providerFingerprint: providerFingerprint,
                    contentType: contentType,
                    categoryID: category.id
                )
                retainedRecordIDs.insert(recordID)

                if let record = existingByID[recordID] {
                    record.providerFingerprint = providerFingerprint
                    record.contentType = contentType
                    record.categoryID = category.id
                    record.name = category.name
                    record.sortIndex = index
                    record.updatedAt = entry.savedAt
                } else {
                    context.insert(
                        PersistedCategoryRecord(
                            id: recordID,
                            providerFingerprint: providerFingerprint,
                            contentType: contentType,
                            categoryID: category.id,
                            name: category.name,
                            sortIndex: index,
                            updatedAt: entry.savedAt
                        )
                    )
                }
            }

            for record in existing where !retainedRecordIDs.contains(record.id) {
                context.delete(record)
            }

            try updateStreamCategoryMetadata(
                providerFingerprint: providerFingerprint,
                contentType: contentType,
                categories: categories,
                context: context
            )
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

    private func updateStreamCategoryMetadata(
        providerFingerprint: String,
        contentType: String,
        categories: [CachedCategoryDTO],
        context: ModelContext
    ) throws {
        guard !categories.isEmpty else { return }

        let categoryNamesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let streams = try context.fetch(
            FetchDescriptor<PersistedStreamRecord>(
                predicate: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.contentType == contentType
                }
            )
        )

        for stream in streams {
            guard let name = categoryNamesByID[stream.categoryID] else { continue }
            stream.categoryName = name
            stream.normalizedCategoryName = Self.normalize(name)
        }
    }

    private static func normalize(_ input: String) -> String {
        input
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
