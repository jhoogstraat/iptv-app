//
//  SearchIndexStore.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import Foundation

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
    private struct SearchDocument: Hashable, Sendable {
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
        let categoryIDs: Set<String>
        let categories: Set<String>
        let normalizedCategories: Set<String>
        let genres: Set<String>
        let normalizedGenres: Set<String>

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
    }

    private struct RankedDocument: Sendable {
        let document: SearchDocument
        let score: Double
        let matchedFields: Set<SearchMatchedField>
    }

    private struct ProviderIndex: Sendable {
        var documentsByKey: [String: SearchDocument] = [:]
        var movieKeys: Set<String> = []
        var seriesKeys: Set<String> = []
        var indexedMovieCategoryIDs: Set<String> = []
        var indexedSeriesCategoryIDs: Set<String> = []
    }

    private var indexesByProvider: [String: ProviderIndex] = [:]

    func upsert(
        videos: [SearchVideoSnapshot],
        contentType: XtreamContentType,
        categoryID: String,
        categoryName: String,
        providerFingerprint: String
    ) {
        guard contentType == .vod || contentType == .series else { return }

        var providerIndex = indexesByProvider[providerFingerprint] ?? ProviderIndex()
        for video in videos {
            let key = Self.makeKey(contentType: contentType, videoID: video.id)
            let cleanedCategoryID = categoryID.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedCategoryName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedCategory = Self.normalize(cleanedCategoryName)
            let playbackContentType = Self.playbackContentType(from: video.contentType, indexedAs: contentType)

            let existing = providerIndex.documentsByKey[key]
            let categoryIDs = (existing?.categoryIDs ?? []).union(cleanedCategoryID.isEmpty ? [] : [cleanedCategoryID])
            let categories = (existing?.categories ?? []).union(cleanedCategoryName.isEmpty ? [] : [cleanedCategoryName])
            let normalizedCategories = (existing?.normalizedCategories ?? []).union(normalizedCategory.isEmpty ? [] : [normalizedCategory])
            let genres = (existing?.genres ?? []).union(cleanedCategoryName.isEmpty ? [] : [cleanedCategoryName])
            let normalizedGenres = (existing?.normalizedGenres ?? []).union(normalizedCategory.isEmpty ? [] : [normalizedCategory])

            let language = video.language?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedLanguage = language.map(Self.normalize)
            let addedAtRaw = video.addedAtRaw?.trimmingCharacters(in: .whitespacesAndNewlines)

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
                categoryIDs: categoryIDs,
                categories: categories,
                normalizedCategories: normalizedCategories,
                genres: genres,
                normalizedGenres: normalizedGenres
            )

            providerIndex.documentsByKey[key] = document
            switch contentType {
            case .vod:
                providerIndex.movieKeys.insert(key)
            case .series:
                providerIndex.seriesKeys.insert(key)
            case .live:
                break
            }
        }

        switch contentType {
        case .vod:
            providerIndex.indexedMovieCategoryIDs.insert(categoryID)
        case .series:
            providerIndex.indexedSeriesCategoryIDs.insert(categoryID)
        case .live:
            break
        }

        indexesByProvider[providerFingerprint] = providerIndex
    }

    func query(_ query: SearchQuery, providerFingerprint: String) -> [SearchResultItem] {
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
            let video = Video(
                id: doc.videoID,
                name: doc.title,
                containerExtension: doc.containerExtension,
                contentType: doc.playbackContentType,
                coverImageURL: doc.coverImageURL,
                tmdbId: nil,
                rating: doc.rating,
                addedAtRaw: doc.addedAtRaw
            )

            return SearchResultItem(
                video: video,
                scope: doc.scope,
                score: item.score,
                matchedFields: item.matchedFields
            )
        }
    }

    func progress(scope: SearchMediaScope, providerFingerprint: String, totalCategories: Int) -> SearchIndexProgress {
        let indexed = indexedCategories(scope: scope, providerFingerprint: providerFingerprint).count
        return SearchIndexProgress(indexedCategories: indexed, totalCategories: totalCategories, scope: scope)
    }

    func facetValues(scope: SearchMediaScope, providerFingerprint: String) -> SearchFacetValues {
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

    func indexedCategories(scope: SearchMediaScope, providerFingerprint: String) -> Set<String> {
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

    func clear(providerFingerprint: String) {
        indexesByProvider[providerFingerprint] = nil
    }

    func clearAll() {
        indexesByProvider.removeAll()
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
