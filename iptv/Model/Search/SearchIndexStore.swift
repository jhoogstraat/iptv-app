//
//  SearchIndexStore.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import Foundation
import SwiftData

protocol SearchIndexSnapshotStore: Sendable {
    func load(providerFingerprint: String) async throws -> SearchIndexStore.ProviderIndex?
    func save(_ index: SearchIndexStore.ProviderIndex, providerFingerprint: String) async throws
    func remove(providerFingerprint: String) async throws
    func removeAll() async throws
}

struct SearchVideoSnapshot: Hashable, Sendable {
    let id: Int
    let name: String
    let containerExtension: String
    let contentType: String
    let coverImageURL: String?
    let rating: Double?
    let addedAtRaw: String?
    let language: String?

    init(
        id: Int,
        name: String,
        containerExtension: String,
        contentType: String,
        coverImageURL: String?,
        rating: Double?,
        addedAtRaw: String?,
        language: String?
    ) {
        self.id = id
        self.name = name
        self.containerExtension = containerExtension
        self.contentType = contentType
        self.coverImageURL = coverImageURL
        self.rating = rating
        self.addedAtRaw = addedAtRaw
        self.language = language
    }

    init(video: Video) {
        self.id = video.id
        self.name = video.name
        self.containerExtension = video.containerExtension
        self.contentType = video.contentType
        self.coverImageURL = video.coverImageURL
        self.rating = video.rating
        self.addedAtRaw = video.addedAtRaw
        self.language = video.language
    }

    init(cachedVideo: CachedVideoDTO) {
        self.id = cachedVideo.id
        self.name = cachedVideo.name
        self.containerExtension = cachedVideo.containerExtension
        self.contentType = cachedVideo.contentType
        self.coverImageURL = cachedVideo.coverImageURL
        self.rating = cachedVideo.rating
        self.addedAtRaw = cachedVideo.added
        self.language = nil
    }
}

actor SearchIndexStore {
    struct ProviderCounts: Hashable, Sendable {
        let movies: Int
        let series: Int
    }

    struct SearchDocument: Codable, Hashable, Sendable {
        let key: String
        let videoID: Int
        let indexedContentType: XtreamContentType
        let playbackContentType: String
        let title: String
        let normalizedTitle: String
        let containerExtension: String
        let coverImageURL: String?
        let rating: Double?
        let addedAtRaw: String?
        let addedAt: Date?
        let language: String?
        let normalizedLanguage: String?
        let categoryNamesByID: [String: String]
        let normalizedCategoryNamesByID: [String: String]

        var scope: SearchMediaScope {
            switch indexedContentType {
            case .vod:
                .movies
            case .series:
                .series
            case .live:
                .all
            }
        }

        var categoryIDs: Set<String> {
            Set(categoryNamesByID.keys)
        }

        var categories: Set<String> {
            Set(categoryNamesByID.values.filter { !$0.isEmpty })
        }

        var normalizedCategories: Set<String> {
            Set(normalizedCategoryNamesByID.values.filter { !$0.isEmpty })
        }

        var genres: Set<String> {
            categories
        }

        var normalizedGenres: Set<String> {
            normalizedCategories
        }
    }

    private struct RankedDocument: Sendable {
        let document: SearchDocument
        let score: Double
        let matchedFields: Set<SearchMatchedField>
    }

    struct ProviderIndex: Codable, Sendable {
        var documentsByKey: [String: SearchDocument] = [:]
        var movieKeys: Set<String> = []
        var seriesKeys: Set<String> = []
        var indexedMovieCategoryIDs: Set<String> = []
        var indexedSeriesCategoryIDs: Set<String> = []

        mutating func insertKey(_ key: String, for contentType: XtreamContentType) {
            switch contentType {
            case .vod:
                movieKeys.insert(key)
            case .series:
                seriesKeys.insert(key)
            case .live:
                break
            }
        }

        mutating func markCategoryIndexed(_ categoryID: String, for contentType: XtreamContentType) {
            guard !categoryID.isEmpty else { return }
            switch contentType {
            case .vod:
                indexedMovieCategoryIDs.insert(categoryID)
            case .series:
                indexedSeriesCategoryIDs.insert(categoryID)
            case .live:
                break
            }
        }

        func removingCategory(contentType: XtreamContentType, categoryID: String) -> ProviderIndex {
            guard !categoryID.isEmpty else { return self }

            var copy = self
            let candidateKeys: Set<String>
            switch contentType {
            case .vod:
                candidateKeys = movieKeys
                copy.indexedMovieCategoryIDs.remove(categoryID)
            case .series:
                candidateKeys = seriesKeys
                copy.indexedSeriesCategoryIDs.remove(categoryID)
            case .live:
                candidateKeys = []
            }

            for key in candidateKeys {
                guard let document = copy.documentsByKey[key] else { continue }
                guard document.categoryIDs.contains(categoryID) else { continue }

                var categoryNamesByID = document.categoryNamesByID
                var normalizedCategoryNamesByID = document.normalizedCategoryNamesByID
                categoryNamesByID.removeValue(forKey: categoryID)
                normalizedCategoryNamesByID.removeValue(forKey: categoryID)

                if categoryNamesByID.isEmpty {
                    copy.documentsByKey.removeValue(forKey: key)
                    copy.movieKeys.remove(key)
                    copy.seriesKeys.remove(key)
                    continue
                }

                copy.documentsByKey[key] = SearchDocument(
                    key: document.key,
                    videoID: document.videoID,
                    indexedContentType: document.indexedContentType,
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
                    categoryNamesByID: categoryNamesByID,
                    normalizedCategoryNamesByID: normalizedCategoryNamesByID
                )
            }

            return copy
        }
    }

    struct ProviderIndexSnapshot: Codable, Sendable {
        static let schemaVersion = 2

        let schemaVersion: Int
        let providerFingerprint: String
        let index: ProviderIndex

        init(providerFingerprint: String, index: ProviderIndex) {
            self.schemaVersion = Self.schemaVersion
            self.providerFingerprint = providerFingerprint
            self.index = index
        }
    }

    actor DiskSnapshotStore: SearchIndexSnapshotStore {
        private let fileManager = FileManager.default
        private let directoryURL: URL
        private let encoder = JSONEncoder()
        private let decoder = JSONDecoder()

        init(directoryURL: URL? = nil) {
            let baseDirectory = directoryURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directoryURL = baseDirectory.appending(path: "SearchIndexSnapshots", directoryHint: .isDirectory)
        }

        fileprivate func load(providerFingerprint: String) async throws -> ProviderIndex? {
            try ensureDirectoryExists()

            let fileURL = fileURL(for: providerFingerprint)
            guard fileManager.fileExists(atPath: fileURL.path()) else { return nil }

            do {
                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                let snapshot = try decoder.decode(ProviderIndexSnapshot.self, from: data)
                guard snapshot.schemaVersion == ProviderIndexSnapshot.schemaVersion,
                      snapshot.providerFingerprint == providerFingerprint else {
                    try? fileManager.removeItem(at: fileURL)
                    return nil
                }
                return snapshot.index
            } catch {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
        }

        fileprivate func save(_ index: ProviderIndex, providerFingerprint: String) async throws {
            try ensureDirectoryExists()
            let snapshot = ProviderIndexSnapshot(providerFingerprint: providerFingerprint, index: index)
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL(for: providerFingerprint), options: [.atomic])
        }

        fileprivate func remove(providerFingerprint: String) async throws {
            let fileURL = fileURL(for: providerFingerprint)
            guard fileManager.fileExists(atPath: fileURL.path()) else { return }
            try? fileManager.removeItem(at: fileURL)
        }

        fileprivate func removeAll() async throws {
            guard fileManager.fileExists(atPath: directoryURL.path()) else { return }
            let files = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }

        private func ensureDirectoryExists() throws {
            if !fileManager.fileExists(atPath: directoryURL.path()) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
        }

        private func fileURL(for providerFingerprint: String) -> URL {
            directoryURL.appending(path: providerFingerprint.snapshotFileName)
        }
    }

    private var indexesByProvider: [String: ProviderIndex] = [:]
    private var hydratedProviders: Set<String> = []
    private let snapshotStore: any SearchIndexSnapshotStore

    init() {
        self.snapshotStore = DiskSnapshotStore()
    }

    init(snapshotDirectoryURL: URL) {
        self.snapshotStore = DiskSnapshotStore(directoryURL: snapshotDirectoryURL)
    }

    init(modelContainer: ModelContainer) {
        self.snapshotStore = SwiftDataSearchIndexSnapshotStore(modelContainer: modelContainer)
    }

    func replaceCategory(
        videos: [SearchVideoSnapshot],
        contentType: XtreamContentType,
        categoryID: String,
        categoryName: String,
        providerFingerprint: String
    ) async {
        guard contentType == .vod || contentType == .series else { return }
        await ensureLoaded(providerFingerprint: providerFingerprint)

        let cleanedCategoryID = categoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCategoryName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategoryName = Self.normalize(cleanedCategoryName)

        var providerIndex = indexesByProvider[providerFingerprint] ?? ProviderIndex()
        providerIndex = providerIndex.removingCategory(
            contentType: contentType,
            categoryID: cleanedCategoryID
        )

        for video in videos {
            let key = Self.makeKey(contentType: contentType, videoID: video.id)
            let playbackContentType = Self.playbackContentType(from: video.contentType, indexedAs: contentType)
            let language = video.language?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedLanguage = language.map(Self.normalize)
            let addedAtRaw = video.addedAtRaw?.trimmingCharacters(in: .whitespacesAndNewlines)

            var categoryNamesByID = providerIndex.documentsByKey[key]?.categoryNamesByID ?? [:]
            var normalizedCategoryNamesByID = providerIndex.documentsByKey[key]?.normalizedCategoryNamesByID ?? [:]

            if !cleanedCategoryID.isEmpty {
                categoryNamesByID[cleanedCategoryID] = cleanedCategoryName
                normalizedCategoryNamesByID[cleanedCategoryID] = normalizedCategoryName
            }

            let document = SearchDocument(
                key: key,
                videoID: video.id,
                indexedContentType: contentType,
                playbackContentType: playbackContentType,
                title: video.name,
                normalizedTitle: Self.normalize(video.name),
                containerExtension: video.containerExtension,
                coverImageURL: video.coverImageURL,
                rating: video.rating,
                addedAtRaw: addedAtRaw,
                addedAt: Self.parseDate(addedAtRaw),
                language: language,
                normalizedLanguage: normalizedLanguage,
                categoryNamesByID: categoryNamesByID,
                normalizedCategoryNamesByID: normalizedCategoryNamesByID
            )

            providerIndex.documentsByKey[key] = document
            providerIndex.insertKey(key, for: contentType)
        }

        providerIndex.markCategoryIndexed(cleanedCategoryID, for: contentType)
        indexesByProvider[providerFingerprint] = providerIndex
        try? await snapshotStore.save(providerIndex, providerFingerprint: providerFingerprint)
    }

    func upsert(
        videos: [SearchVideoSnapshot],
        contentType: XtreamContentType,
        categoryID: String,
        categoryName: String,
        providerFingerprint: String
    ) async {
        await replaceCategory(
            videos: videos,
            contentType: contentType,
            categoryID: categoryID,
            categoryName: categoryName,
            providerFingerprint: providerFingerprint
        )
    }

    func removeCategory(
        contentType: XtreamContentType,
        categoryID: String,
        providerFingerprint: String
    ) async {
        guard contentType == .vod || contentType == .series else { return }
        await ensureLoaded(providerFingerprint: providerFingerprint)

        var providerIndex = indexesByProvider[providerFingerprint] ?? ProviderIndex()
        providerIndex = providerIndex.removingCategory(
            contentType: contentType,
            categoryID: categoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        indexesByProvider[providerFingerprint] = providerIndex
        try? await snapshotStore.save(providerIndex, providerFingerprint: providerFingerprint)
    }

    func query(_ query: SearchQuery, providerFingerprint: String) async -> [SearchResultItem] {
        await ensureLoaded(providerFingerprint: providerFingerprint)
        guard let providerIndex = indexesByProvider[providerFingerprint] else { return [] }

        let now = Date()
        let normalizedQuery = Self.normalize(query.text)
        let normalizedGenreFilters = Set(query.filters.genres.map(Self.normalize))
        let normalizedLanguageFilters = Set(query.filters.languages.map(Self.normalize))

        let candidateKeys: Set<String>
        switch query.scope {
        case .all:
            candidateKeys = providerIndex.movieKeys.union(providerIndex.seriesKeys)
        case .movies:
            candidateKeys = providerIndex.movieKeys
        case .series:
            candidateKeys = providerIndex.seriesKeys
        }

        var rankedDocuments: [RankedDocument] = []
        rankedDocuments.reserveCapacity(candidateKeys.count)

        for key in candidateKeys {
            guard let doc = providerIndex.documentsByKey[key] else { continue }
            guard matchesFilters(
                doc: doc,
                filters: query.filters,
                normalizedGenreFilters: normalizedGenreFilters,
                normalizedLanguageFilters: normalizedLanguageFilters,
                now: now
            ) else { continue }

            let match = computeMatch(for: doc, normalizedQuery: normalizedQuery, now: now)
            if !normalizedQuery.isEmpty && match.matchedFields.isEmpty {
                continue
            }

            rankedDocuments.append(
                RankedDocument(
                    document: doc,
                    score: match.score,
                    matchedFields: match.matchedFields
                )
            )
        }

        return sort(rankedDocuments, using: query.sort).map { item in
            let doc = item.document
            return SearchResultItem(
                summary: SearchVideoSummary(
                    videoID: doc.videoID,
                    name: doc.title,
                    containerExtension: doc.containerExtension,
                    contentType: doc.playbackContentType,
                    coverImageURL: doc.coverImageURL,
                    artworkURL: doc.coverImageURL.flatMap(URL.init(string:)),
                    rating: doc.rating,
                    displayRating: Self.formatRating(doc.rating),
                    addedAtRaw: doc.addedAtRaw,
                    language: doc.language
                ),
                scope: doc.scope,
                score: item.score,
                matchedFields: item.matchedFields
            )
        }
    }

    func progress(scope: SearchMediaScope, providerFingerprint: String, totalCategories: Int) async -> SearchIndexProgress {
        let indexed = await indexedCategories(scope: scope, providerFingerprint: providerFingerprint).count
        return SearchIndexProgress(indexedCategories: indexed, totalCategories: totalCategories, scope: scope)
    }

    func facetValues(scope: SearchMediaScope, providerFingerprint: String) async -> SearchFacetValues {
        await ensureLoaded(providerFingerprint: providerFingerprint)
        guard let providerIndex = indexesByProvider[providerFingerprint] else {
            return SearchFacetValues(genres: [], languages: [])
        }

        let candidateKeys: Set<String>
        switch scope {
        case .all:
            candidateKeys = providerIndex.movieKeys.union(providerIndex.seriesKeys)
        case .movies:
            candidateKeys = providerIndex.movieKeys
        case .series:
            candidateKeys = providerIndex.seriesKeys
        }

        var genres = Set<String>()
        var languages = Set<String>()
        for key in candidateKeys {
            guard let document = providerIndex.documentsByKey[key] else { continue }
            genres.formUnion(document.genres)
            if let language = document.language, !language.isEmpty {
                languages.insert(language)
            }
        }

        return SearchFacetValues(
            genres: genres.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
            languages: languages.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        )
    }

    func indexedCategories(scope: SearchMediaScope, providerFingerprint: String) async -> Set<String> {
        await ensureLoaded(providerFingerprint: providerFingerprint)
        guard let providerIndex = indexesByProvider[providerFingerprint] else { return [] }
        switch scope {
        case .movies:
            return providerIndex.indexedMovieCategoryIDs
        case .series:
            return providerIndex.indexedSeriesCategoryIDs
        case .all:
            return providerIndex.indexedMovieCategoryIDs.union(providerIndex.indexedSeriesCategoryIDs)
        }
    }

    func providerCounts(providerFingerprint: String) async -> ProviderCounts {
        await ensureLoaded(providerFingerprint: providerFingerprint)
        guard let providerIndex = indexesByProvider[providerFingerprint] else {
            return ProviderCounts(movies: 0, series: 0)
        }
        return ProviderCounts(
            movies: providerIndex.movieKeys.count,
            series: providerIndex.seriesKeys.count
        )
    }

    func clear(providerFingerprint: String) async {
        indexesByProvider[providerFingerprint] = nil
        hydratedProviders.insert(providerFingerprint)
        try? await snapshotStore.remove(providerFingerprint: providerFingerprint)
    }

    func clearAll() async {
        indexesByProvider.removeAll()
        hydratedProviders.removeAll()
        try? await snapshotStore.removeAll()
    }

    private func ensureLoaded(providerFingerprint: String) async {
        guard !hydratedProviders.contains(providerFingerprint) else { return }
        hydratedProviders.insert(providerFingerprint)
        indexesByProvider[providerFingerprint] = try? await snapshotStore.load(providerFingerprint: providerFingerprint)
    }

    private static func formatRating(_ rating: Double?) -> String? {
        guard let rating else { return nil }
        return rating.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
    }

    private func matchesFilters(
        doc: SearchDocument,
        filters: SearchFilters,
        normalizedGenreFilters: Set<String>,
        normalizedLanguageFilters: Set<String>,
        now: Date
    ) -> Bool {
        if let minRating = filters.minRating {
            guard let rating = doc.rating, rating >= minRating else { return false }
        }
        if let maxRating = filters.maxRating {
            guard let rating = doc.rating, rating <= maxRating else { return false }
        }
        if !normalizedGenreFilters.isEmpty && doc.normalizedGenres.isDisjoint(with: normalizedGenreFilters) {
            return false
        }
        if !normalizedLanguageFilters.isEmpty {
            guard let language = doc.normalizedLanguage, normalizedLanguageFilters.contains(language) else { return false }
        }
        if !filters.categoryIDs.isEmpty && doc.categoryIDs.isDisjoint(with: filters.categoryIDs) {
            return false
        }
        if let dayCount = filters.addedWindow.dayCount {
            guard let addedAt = doc.addedAt else { return false }
            guard let threshold = Calendar.current.date(byAdding: .day, value: -dayCount, to: now) else { return false }
            guard addedAt >= threshold else { return false }
        }
        return true
    }

    private func computeMatch(for doc: SearchDocument, normalizedQuery: String, now: Date) -> (score: Double, matchedFields: Set<SearchMatchedField>) {
        guard !normalizedQuery.isEmpty else {
            return (baseScore(for: doc, now: now), [])
        }

        var matchedFields: Set<SearchMatchedField> = []
        var score = 0.0

        if doc.normalizedTitle.hasPrefix(normalizedQuery) {
            matchedFields.insert(.titlePrefix)
            score += 100
        } else if doc.normalizedTitle.contains(normalizedQuery) {
            matchedFields.insert(.titleContains)
            score += 50
        }

        var metadataHits = 0
        if doc.normalizedGenres.contains(where: { $0.contains(normalizedQuery) }) {
            matchedFields.insert(.genre)
            metadataHits += 1
        }
        if doc.normalizedCategories.contains(where: { $0.contains(normalizedQuery) }) {
            matchedFields.insert(.category)
            metadataHits += 1
        }
        if let language = doc.normalizedLanguage, language.contains(normalizedQuery) {
            matchedFields.insert(.language)
            metadataHits += 1
        }

        score += Double(min(metadataHits, 2) * 20)
        score += baseScore(for: doc, now: now)
        return (score, matchedFields)
    }

    private func baseScore(for doc: SearchDocument, now: Date) -> Double {
        var score = 0.0
        if let rating = doc.rating {
            score += min(max(rating / 10.0, 0), 1) * 10.0
        }
        if let addedAt = doc.addedAt {
            let ageDays = max(0, now.timeIntervalSince(addedAt) / 86_400)
            let normalizedRecency = max(0, 1 - min(ageDays / 365.0, 1))
            score += normalizedRecency * 5.0
        }
        return score
    }

    private func sort(_ items: [RankedDocument], using sort: SearchSort) -> [RankedDocument] {
        switch sort {
        case .relevance:
            return items.sorted { lhs, rhs in
                compare(lhs, rhs, primary: { $0.score }, descending: true)
            }
        case .newest:
            return items.sorted { lhs, rhs in
                compare(lhs, rhs, primary: { $0.document.addedAt?.timeIntervalSinceReferenceDate ?? .leastNormalMagnitude }, descending: true)
            }
        case .rating:
            return items.sorted { lhs, rhs in
                compare(lhs, rhs, primary: { $0.document.rating ?? .leastNormalMagnitude }, descending: true)
            }
        case .title:
            return items.sorted { lhs, rhs in
                let titleOrder = lhs.document.title.localizedCaseInsensitiveCompare(rhs.document.title)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }
                return lhs.document.videoID < rhs.document.videoID
            }
        }
    }

    private func compare(
        _ lhs: RankedDocument,
        _ rhs: RankedDocument,
        primary: (RankedDocument) -> Double,
        descending: Bool
    ) -> Bool {
        let leftPrimary = primary(lhs)
        let rightPrimary = primary(rhs)
        if leftPrimary != rightPrimary {
            return descending ? leftPrimary > rightPrimary : leftPrimary < rightPrimary
        }

        let leftRating = lhs.document.rating ?? .leastNormalMagnitude
        let rightRating = rhs.document.rating ?? .leastNormalMagnitude
        if leftRating != rightRating {
            return leftRating > rightRating
        }

        let leftAdded = lhs.document.addedAt?.timeIntervalSinceReferenceDate ?? .leastNormalMagnitude
        let rightAdded = rhs.document.addedAt?.timeIntervalSinceReferenceDate ?? .leastNormalMagnitude
        if leftAdded != rightAdded {
            return leftAdded > rightAdded
        }

        let titleOrder = lhs.document.title.localizedCaseInsensitiveCompare(rhs.document.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        return lhs.document.videoID < rhs.document.videoID
    }

    private static func makeKey(contentType: XtreamContentType, videoID: Int) -> String {
        "\(contentType.rawValue):\(videoID)"
    }

    private static func playbackContentType(from rawValue: String, indexedAs contentType: XtreamContentType) -> String {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "movie" {
            return "movie"
        }
        if let parsed = XtreamContentType(rawValue: normalized) {
            return parsed.playbackPathComponent
        }
        return normalized.isEmpty ? contentType.playbackPathComponent : normalized
    }

    private static func normalize(_ input: String) -> String {
        input
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

private extension String {
    nonisolated
    var snapshotFileName: String {
        let encoded = Data(utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return encoded + ".json"
    }
}
