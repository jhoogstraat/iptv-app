//
//  CatalogueStore.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import Foundation
import SwiftData

enum LoadReason: Sendable {
    case userVisible
    case backgroundSync
    case detailPrefetch
}

struct CatalogueBootstrapSnapshot: Sendable {
    let vodCategories: [CachedCategoryDTO]
    let seriesCategories: [CachedCategoryDTO]
}

typealias RefreshCandidate = BackgroundCatalogueRefreshTarget

actor CatalogueStore {
    private struct ProviderState: Sendable {
        let config: ProviderConfig
        let fingerprint: String
        let excludedCategoryPrefixes: Set<String>
    }

    private struct CategoryTaskKey: Hashable {
        let providerFingerprint: String
        let contentType: XtreamContentType
        let categoryID: String
    }

    fileprivate struct RefreshStateSnapshot {
        let contentType: XtreamContentType
        let categoryID: String
        let lastSuccessfulRefreshAt: Date?
        let nextEligibleRefreshAt: Date?
    }

    private struct SyncObserver {
        let providerFingerprint: String
        let scope: SearchMediaScope
        let continuation: AsyncStream<CatalogueSyncProgress>.Continuation
    }

    fileprivate struct SearchDocument: Sendable {
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

        var genres: Set<String> {
            Set(categoryNamesByID.values.filter { !$0.isEmpty })
        }

        var normalizedGenres: Set<String> {
            Set(normalizedCategoryNamesByID.values.filter { !$0.isEmpty })
        }
    }

    private struct RankedDocument: Sendable {
        let document: SearchDocument
        let score: Double
        let matchedFields: Set<SearchMatchedField>
    }

    private let providerStore: ProviderStore
    private let persistence: CataloguePersistence
    private let cacheManager: CatalogCacheManager
    private let metadataCacheManager: CatalogMetadataCacheManager
    private let now: @Sendable () -> Date
    private let categoryListRefreshInterval: TimeInterval
    private let categoryRefreshInterval: TimeInterval

    private var inFlightStreamLoads: [CategoryTaskKey: Task<[CachedVideoDTO], Error>] = [:]
    private var summaryCache: [String: ProviderCatalogueSummary] = [:]
    private var syncObservers: [UUID: SyncObserver] = [:]

    init(
        providerStore: ProviderStore,
        modelContainer: ModelContainer,
        cacheManager: CatalogCacheManager? = nil,
        metadataCacheManager: CatalogMetadataCacheManager? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        categoryListRefreshInterval: TimeInterval = 12 * 60 * 60,
        categoryRefreshInterval: TimeInterval = 24 * 60 * 60
    ) {
        self.providerStore = providerStore
        self.persistence = CataloguePersistence(modelContainer: modelContainer)
        self.cacheManager = cacheManager ?? CatalogCacheManager(
            store: StreamListCachePersistence(modelContainer: modelContainer)
        )
        self.metadataCacheManager = metadataCacheManager ?? CatalogMetadataCacheManager(
            store: CatalogMetadataCachePersistence(modelContainer: modelContainer)
        )
        self.now = now
        self.categoryListRefreshInterval = categoryListRefreshInterval
        self.categoryRefreshInterval = categoryRefreshInterval
    }

    func resetTransientState() async {
        inFlightStreamLoads.values.forEach { $0.cancel() }
        inFlightStreamLoads.removeAll()
        await cacheManager.clearMemoryCache()
        await metadataCacheManager.clearMemoryCache()
    }

    func bootstrap(providerFingerprint: String) async throws -> CatalogueBootstrapSnapshot {
        let state = try await providerState()
        guard state.fingerprint == providerFingerprint else { throw CancellationError() }

        try await refreshCategoryListsIfNeeded(providerState: state)
        let vodCategories = try await loadCategories(contentType: .vod, policy: .readThrough, providerState: state)
        let seriesCategories = try await loadCategories(contentType: .series, policy: .readThrough, providerState: state)
        return CatalogueBootstrapSnapshot(vodCategories: vodCategories, seriesCategories: seriesCategories)
    }

    func ensureBootstrapLoaded() async throws {
        let state = try await providerState()
        _ = try await bootstrap(providerFingerprint: state.fingerprint)
    }

    func loadCategories(
        contentType: XtreamContentType,
        policy: CatalogLoadPolicy
    ) async throws -> [CachedCategoryDTO] {
        let state = try await providerState()
        return try await loadCategories(contentType: contentType, policy: policy, providerState: state)
    }

    func loadCategory(
        contentType: XtreamContentType,
        categoryID: String,
        categoryName: String,
        policy: CatalogLoadPolicy,
        reason: LoadReason
    ) async throws -> [CachedVideoDTO] {
        let state = try await providerState()
        let category = Category(id: categoryID, name: categoryName)
        return try await loadStreams(
            in: category,
            contentType: contentType,
            policy: policy,
            reason: reason,
            providerState: state
        )
    }

    func loadMovieInfo(
        video: Video,
        policy: CatalogLoadPolicy,
        reason: LoadReason
    ) async throws -> CachedVideoInfoDTO {
        let state = try await providerState()
        return try await loadVodInfo(video, policy: policy, reason: reason, providerState: state)
    }

    func loadSeriesInfo(
        video: Video,
        policy: CatalogLoadPolicy,
        reason: LoadReason
    ) async throws -> XtreamSeries {
        let state = try await providerState()
        return try await loadSeriesInfo(video, policy: policy, reason: reason, providerState: state)
    }

    func search(_ query: SearchQuery) async throws -> [SearchResultItem] {
        let state = try await providerState()
        let documents = try await loadDocuments(
            providerFingerprint: state.fingerprint,
            acceptedContentTypes: query.scope.acceptedContentTypes
        )

        let currentDate = now()
        let normalizedQuery = Self.normalize(query.text)
        let normalizedGenreFilters = Set(query.filters.genres.map(Self.normalize))
        let normalizedLanguageFilters = Set(query.filters.languages.map(Self.normalize))

        var rankedDocuments: [RankedDocument] = []
        rankedDocuments.reserveCapacity(documents.count)

        for document in documents {
            guard matchesFilters(
                document: document,
                filters: query.filters,
                normalizedGenreFilters: normalizedGenreFilters,
                normalizedLanguageFilters: normalizedLanguageFilters,
                now: currentDate
            ) else { continue }

            let match = computeMatch(for: document, normalizedQuery: normalizedQuery, now: currentDate)
            if !normalizedQuery.isEmpty && match.matchedFields.isEmpty {
                continue
            }

            rankedDocuments.append(
                RankedDocument(document: document, score: match.score, matchedFields: match.matchedFields)
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

    func facetValues(scope: SearchMediaScope) async throws -> SearchFacetValues {
        let state = try await providerState()
        let documents = try await loadDocuments(
            providerFingerprint: state.fingerprint,
            acceptedContentTypes: scope.acceptedContentTypes
        )

        var genres = Set<String>()
        var languages = Set<String>()
        for document in documents {
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

    func syncProgress(scope: SearchMediaScope) async throws -> CatalogueSyncProgress {
        let state = try await providerState()
        return try await syncProgress(scope: scope, providerFingerprint: state.fingerprint)
    }

    func observeSyncProgress(scope: SearchMediaScope) async throws -> AsyncStream<CatalogueSyncProgress> {
        let state = try await providerState()
        let initialProgress = try await syncProgress(scope: scope, providerFingerprint: state.fingerprint)
        let observerID = UUID()
        var storedContinuation: AsyncStream<CatalogueSyncProgress>.Continuation?
        let stream = AsyncStream<CatalogueSyncProgress>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            storedContinuation = continuation
        }

        guard let continuation = storedContinuation else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        continuation.onTermination = { _ in
            Task { await self.removeSyncObserver(id: observerID) }
        }
        syncObservers[observerID] = SyncObserver(
            providerFingerprint: state.fingerprint,
            scope: scope,
            continuation: continuation
        )
        continuation.yield(initialProgress)
        return stream
    }

    func nextRefreshCandidate() async throws -> RefreshCandidate? {
        let state = try await providerState()
        try await refreshCategoryListsIfNeeded(providerState: state)

        let categories = try await loadStoredCategories(
            providerFingerprint: state.fingerprint,
            acceptedContentTypes: [XtreamContentType.vod.rawValue, XtreamContentType.series.rawValue]
        )
        guard !categories.isEmpty else { return nil }

        let streamRecords = try await loadStoredStreamRecords(providerFingerprint: state.fingerprint)
        let cachedKeys = Set(streamRecords.map { "\($0.contentType):\($0.categoryID)" })
        let states = try await refreshStates(providerFingerprint: state.fingerprint)
        let currentDate = now()
        let staleThreshold = currentDate.addingTimeInterval(-categoryRefreshInterval)

        let candidates = categories.compactMap { category -> RefreshCandidate? in
            guard let contentType = XtreamContentType(rawValue: category.contentType),
                  contentType == .vod || contentType == .series else {
                return nil
            }

            let key = "\(category.contentType):\(category.categoryID)"
            let refreshState = states[key]

            if let nextEligibleRefreshAt = refreshState?.nextEligibleRefreshAt, nextEligibleRefreshAt > currentDate {
                return nil
            }

            let hasCachedCategory = cachedKeys.contains(key)
            if hasCachedCategory,
               let lastSuccessfulRefreshAt = refreshState?.lastSuccessfulRefreshAt,
               lastSuccessfulRefreshAt > staleThreshold {
                return nil
            }

            return RefreshCandidate(
                providerFingerprint: state.fingerprint,
                contentType: contentType,
                categoryID: category.categoryID,
                categoryName: category.name,
                sortIndex: category.sortIndex
            )
        }

        return candidates.sorted(by: { lhs, rhs in
            let leftKey = "\(lhs.contentType.rawValue):\(lhs.categoryID)"
            let rightKey = "\(rhs.contentType.rawValue):\(rhs.categoryID)"
            let leftCached = cachedKeys.contains(leftKey)
            let rightCached = cachedKeys.contains(rightKey)
            if leftCached != rightCached {
                return !leftCached
            }

            let leftDate = states[leftKey]?.lastSuccessfulRefreshAt ?? .distantPast
            let rightDate = states[rightKey]?.lastSuccessfulRefreshAt ?? .distantPast
            if leftDate != rightDate {
                return leftDate < rightDate
            }

            if lhs.contentType != rhs.contentType {
                return lhs.contentType.rawValue < rhs.contentType.rawValue
            }
            return lhs.sortIndex < rhs.sortIndex
        }).first
    }

    func refreshCategory(_ candidate: RefreshCandidate) async throws {
        _ = try await loadCategory(
            contentType: candidate.contentType,
            categoryID: candidate.categoryID,
            categoryName: candidate.categoryName,
            policy: .forceRefresh,
            reason: .backgroundSync
        )
    }

    func providerCatalogueSummary() async throws -> ProviderCatalogueSummary {
        let state = try await providerState()
        if let cached = summaryCache[state.fingerprint] {
            return cached
        }

        let records = try await loadStoredStreamRecords(providerFingerprint: state.fingerprint)
        let movieCount = Set(records.filter { $0.contentType == XtreamContentType.vod.rawValue }.map(\.videoID)).count
        let seriesCount = Set(records.filter { $0.contentType == XtreamContentType.series.rawValue }.map(\.videoID)).count

        let categories = try await loadStoredCategories(
            providerFingerprint: state.fingerprint,
            acceptedContentTypes: [XtreamContentType.vod.rawValue, XtreamContentType.series.rawValue]
        )
        let indexedMovieCategories = try await loadIndexedCategories(scope: .movies, providerFingerprint: state.fingerprint).count
        let indexedSeriesCategories = try await loadIndexedCategories(scope: .series, providerFingerprint: state.fingerprint).count

        let summary = ProviderCatalogueSummary(
            movieCount: movieCount,
            seriesCount: seriesCount,
            syncedMovieCategories: indexedMovieCategories,
            totalMovieCategories: categories.filter { $0.contentType == XtreamContentType.vod.rawValue }.count,
            syncedSeriesCategories: indexedSeriesCategories,
            totalSeriesCategories: categories.filter { $0.contentType == XtreamContentType.series.rawValue }.count
        )
        summaryCache[state.fingerprint] = summary
        return summary
    }

    func clearAllCaches() async throws {
        let state = try? await providerState()
        await cacheManager.clearMemoryCache()
        await metadataCacheManager.clearMemoryCache()
        guard let state else { return }
        try await cacheManager.removeAll(for: state.fingerprint)
        try await metadataCacheManager.removeAll(for: state.fingerprint)
        try await removeAllRefreshStates(providerFingerprint: state.fingerprint)
        summaryCache[state.fingerprint] = nil
        await emitSyncProgressUpdates(
            providerFingerprint: state.fingerprint,
            affectedScopes: [.movies, .series, .all]
        )
    }

    private func providerState() async throws -> ProviderState {
        try await MainActor.run {
            let config = try providerStore.requiredConfiguration()
            let fingerprint = ProviderCacheFingerprint.make(from: config)
            let excludedPrefixes = Set(providerStore.excludedCategoryPrefixes())
            return ProviderState(
                config: config,
                fingerprint: fingerprint,
                excludedCategoryPrefixes: excludedPrefixes
            )
        }
    }

    private func service(for state: ProviderState) -> XtreamService {
        XtreamService(
            .shared,
            baseURL: state.config.apiURL,
            username: state.config.username,
            password: state.config.password
        )
    }

    private func metadataKey(
        kind: CatalogMetadataKind,
        resourceID: String,
        providerFingerprint: String
    ) -> CatalogMetadataCacheKey {
        CatalogMetadataCacheKey(providerFingerprint: providerFingerprint, kind: kind, resourceID: resourceID)
    }

    private func cacheKey(
        categoryID: String,
        contentType: XtreamContentType,
        providerFingerprint: String
    ) -> StreamListCacheKey {
        StreamListCacheKey(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID,
            pageToken: nil
        )
    }

    private func applyCategoryVisibility(
        to categories: [CachedCategoryDTO],
        excludedPrefixes: Set<String>
    ) -> [CachedCategoryDTO] {
        categories.filter { category in
            let prefix = LanguageTaggedText(category.name).languageCode?.uppercased()
            guard let prefix else { return true }
            return !excludedPrefixes.contains(prefix)
        }
    }

    private func loadCategories(
        contentType: XtreamContentType,
        policy: CatalogLoadPolicy,
        providerState state: ProviderState
    ) async throws -> [CachedCategoryDTO] {
        let key = metadataKey(
            kind: contentType == .vod ? .vodCategories : .seriesCategories,
            resourceID: "all",
            providerFingerprint: state.fingerprint
        )

        let cachedPayload = try await metadataCacheManager.cachedPayload(for: key)
        let cachedCategories = try cachedPayload.map {
            try decode([CachedCategoryDTO].self, from: $0.value)
        }

        let categories: [CachedCategoryDTO]
        switch policy {
        case .cacheOnly:
            guard let cachedCategories else { throw CatalogError.cacheUnavailable }
            categories = cachedCategories
        case .readThrough:
            if let cachedCategories {
                categories = cachedCategories
            } else {
                categories = try await refreshCategories(
                    contentType: contentType,
                    providerState: state,
                    key: key
                )
            }
        case .forceRefresh:
            categories = try await refreshCategories(
                contentType: contentType,
                providerState: state,
                key: key
            )
        }

        return applyCategoryVisibility(to: categories, excludedPrefixes: state.excludedCategoryPrefixes)
    }

    private func refreshCategories(
        contentType: XtreamContentType,
        providerState state: ProviderState,
        key: CatalogMetadataCacheKey
    ) async throws -> [CachedCategoryDTO] {
        let previous = try await cachedCategoryDTOs(for: key)
        let service = service(for: state)
        let payload = try await metadataCacheManager.refreshPayload(for: key) {
            let categories = try await service.getCategories(of: contentType).map(CachedCategoryDTO.init)
            return try JSONEncoder().encode(categories)
        }
        let freshCategories = try decode([CachedCategoryDTO].self, from: payload)
        try await reconcileCategoryRefresh(
            oldCategories: previous,
            freshCategories: freshCategories,
            contentType: contentType,
            providerFingerprint: state.fingerprint
        )
        summaryCache[state.fingerprint] = nil
        if Set(previous.map(\.id)) != Set(freshCategories.map(\.id)) {
            await emitSyncProgressUpdates(
                providerFingerprint: state.fingerprint,
                affectedScopes: affectedScopes(for: contentType)
            )
        }
        return freshCategories
    }

    private func cachedCategoryDTOs(for key: CatalogMetadataCacheKey) async throws -> [CachedCategoryDTO] {
        guard let cached = try await metadataCacheManager.cachedPayload(for: key) else { return [] }
        return try decode([CachedCategoryDTO].self, from: cached.value)
    }

    private func loadStreams(
        in category: Category,
        contentType: XtreamContentType,
        policy: CatalogLoadPolicy,
        reason: LoadReason,
        providerState state: ProviderState
    ) async throws -> [CachedVideoDTO] {
        let key = cacheKey(categoryID: category.id, contentType: contentType, providerFingerprint: state.fingerprint)
        switch policy {
        case .cacheOnly:
            if let cached = try await cacheManager.cachedValue(for: key) {
                return cached.value
            }
            throw CatalogError.cacheUnavailable
        case .readThrough:
            if let cached = try await cacheManager.cachedValue(for: key) {
                return cached.value
            }
        case .forceRefresh:
            break
        }

        switch reason {
        case .userVisible, .detailPrefetch, .backgroundSync:
            return try await fetchAndPersistCategoryStreams(
                key: key,
                category: category,
                contentType: contentType,
                providerState: state
            )
        }
    }

    private func fetchAndPersistCategoryStreams(
        key: StreamListCacheKey,
        category: Category,
        contentType: XtreamContentType,
        providerState state: ProviderState
    ) async throws -> [CachedVideoDTO] {
        let taskKey = CategoryTaskKey(
            providerFingerprint: key.providerFingerprint,
            contentType: contentType,
            categoryID: category.id
        )

        if let inFlight = inFlightStreamLoads[taskKey] {
            return try await inFlight.value
        }

        let service = service(for: state)
        let categoryID = category.id
        let task = Task(priority: .utility) { [cacheManager, metadataCacheManager] in
            let previousVideos = try await cacheManager.entry(for: key)?.videos ?? []
            let timestamp = self.now()
            try await self.recordCategoryRefreshAttempt(
                providerFingerprint: key.providerFingerprint,
                contentType: contentType,
                categoryID: categoryID,
                at: timestamp
            )

            do {
                let fresh = try await cacheManager.refreshValue(for: key) {
                    switch contentType {
                    case .vod:
                        return try await service.getStreams(of: .vod, in: categoryID).map { CachedVideoDTO(from: $0) }
                    case .series:
                        return try await service.getSeries(in: categoryID).map { CachedVideoDTO(from: $0) }
                    case .live:
                        return []
                    }
                }
                try await self.recordCategoryRefreshSuccess(
                    providerFingerprint: key.providerFingerprint,
                    contentType: contentType,
                    categoryID: categoryID,
                    at: timestamp
                )
                let removedVideoIDs = Set(previousVideos.map(\.id)).subtracting(fresh.map(\.id))
                await self.pruneOrphanedDetailMetadata(
                    videoIDs: removedVideoIDs,
                    contentType: contentType,
                    providerFingerprint: key.providerFingerprint,
                    metadataCacheManager: metadataCacheManager
                )
                self.summaryCache[key.providerFingerprint] = nil
                return fresh
            } catch {
                try await self.recordCategoryRefreshFailure(
                    providerFingerprint: key.providerFingerprint,
                    contentType: contentType,
                    categoryID: categoryID,
                    error: error.localizedDescription,
                    at: timestamp
                )
                throw error
            }
        }

        inFlightStreamLoads[taskKey] = task
        defer { inFlightStreamLoads[taskKey] = nil }
        return try await task.value
    }

    private func loadVodInfo(
        _ video: Video,
        policy: CatalogLoadPolicy,
        reason: LoadReason,
        providerState state: ProviderState
    ) async throws -> CachedVideoInfoDTO {
        let key = metadataKey(kind: .vodInfo, resourceID: String(video.id), providerFingerprint: state.fingerprint)
        let cachedPayload = try await metadataCacheManager.cachedPayload(for: key)
        switch policy {
        case .cacheOnly:
            guard let cachedPayload else { throw CatalogError.cacheUnavailable }
            return try decode(CachedVideoInfoDTO.self, from: cachedPayload.value)
        case .readThrough:
            if let cachedPayload {
                return try decode(CachedVideoInfoDTO.self, from: cachedPayload.value)
            }
        case .forceRefresh:
            break
        }

        let service = service(for: state)
        let videoID = video.id
        let payload = try await metadataCacheManager.refreshPayload(for: key) {
            let dto = try await service.getVodInfo(of: String(videoID))
            return try JSONEncoder().encode(CachedVideoInfoDTO(VideoInfo(from: dto)))
        }
        return try decode(CachedVideoInfoDTO.self, from: payload)
    }

    private func loadSeriesInfo(
        _ video: Video,
        policy: CatalogLoadPolicy,
        reason: LoadReason,
        providerState state: ProviderState
    ) async throws -> XtreamSeries {
        let key = metadataKey(kind: .seriesInfo, resourceID: String(video.id), providerFingerprint: state.fingerprint)
        let cachedPayload = try await metadataCacheManager.cachedPayload(for: key)
        switch policy {
        case .cacheOnly:
            guard let cachedPayload else { throw CatalogError.cacheUnavailable }
            return try decode(XtreamSeries.self, from: cachedPayload.value)
        case .readThrough:
            if let cachedPayload {
                return try decode(XtreamSeries.self, from: cachedPayload.value)
            }
        case .forceRefresh:
            break
        }

        let service = service(for: state)
        let videoID = video.id
        let payload = try await metadataCacheManager.refreshPayload(for: key) {
            try JSONEncoder().encode(try await service.getSeriesInfo(of: String(videoID)))
        }
        return try decode(XtreamSeries.self, from: payload)
    }

    private func refreshCategoryListsIfNeeded(providerState state: ProviderState) async throws {
        let currentDate = now()
        let vodKey = metadataKey(kind: .vodCategories, resourceID: "all", providerFingerprint: state.fingerprint)
        let seriesKey = metadataKey(kind: .seriesCategories, resourceID: "all", providerFingerprint: state.fingerprint)

        if let cached = try await metadataCacheManager.cachedPayload(for: vodKey),
           currentDate.timeIntervalSince(cached.savedAt) > categoryListRefreshInterval {
            _ = try await refreshCategories(contentType: .vod, providerState: state, key: vodKey)
        }

        if let cached = try await metadataCacheManager.cachedPayload(for: seriesKey),
           currentDate.timeIntervalSince(cached.savedAt) > categoryListRefreshInterval {
            _ = try await refreshCategories(contentType: .series, providerState: state, key: seriesKey)
        }
    }

    private func reconcileCategoryRefresh(
        oldCategories: [CachedCategoryDTO],
        freshCategories: [CachedCategoryDTO],
        contentType: XtreamContentType,
        providerFingerprint: String
    ) async throws {
        let freshIDs = Set(freshCategories.map(\.id))
        let removedCategories = oldCategories.filter { !freshIDs.contains($0.id) }

        for removedCategory in removedCategories {
            let key = cacheKey(
                categoryID: removedCategory.id,
                contentType: contentType,
                providerFingerprint: providerFingerprint
            )
            let removedVideos = try await cacheManager.entry(for: key)?.videos ?? []
            try await cacheManager.removeValue(for: key)
            try await deleteCategoryRefreshState(
                providerFingerprint: providerFingerprint,
                contentType: contentType,
                categoryID: removedCategory.id
            )
            let removedVideoIDs = Set(removedVideos.map(\.id))
            await pruneOrphanedDetailMetadata(
                videoIDs: removedVideoIDs,
                contentType: contentType,
                providerFingerprint: providerFingerprint,
                metadataCacheManager: metadataCacheManager
            )
        }
    }

    private func pruneOrphanedDetailMetadata(
        videoIDs: Set<Int>,
        contentType: XtreamContentType,
        providerFingerprint: String,
        metadataCacheManager: CatalogMetadataCacheManager
    ) async {
        guard contentType == .vod || contentType == .series else { return }

        let entries = (try? await cacheManager.entries(providerFingerprint: providerFingerprint)) ?? []
        let referencedIDs = Set(
            entries
                .filter { $0.key.contentType == contentType }
                .flatMap { $0.videos.map(\.id) }
        )

        for videoID in videoIDs where !referencedIDs.contains(videoID) {
            switch contentType {
            case .vod:
                let key = metadataKey(kind: .vodInfo, resourceID: String(videoID), providerFingerprint: providerFingerprint)
                try? await metadataCacheManager.removeValue(for: key)
            case .series:
                let key = metadataKey(kind: .seriesInfo, resourceID: String(videoID), providerFingerprint: providerFingerprint)
                try? await metadataCacheManager.removeValue(for: key)
            case .live:
                break
            }
        }
    }

    private func loadStoredCategories(
        providerFingerprint: String,
        acceptedContentTypes: Set<String>
    ) async throws -> [PersistedCategoryRecord] {
        try await persistence.loadStoredCategories(
            providerFingerprint: providerFingerprint,
            acceptedContentTypes: acceptedContentTypes
        )
    }

    private func loadStoredStreamRecords(providerFingerprint: String) async throws -> [PersistedStreamRecord] {
        try await persistence.loadStoredStreamRecords(providerFingerprint: providerFingerprint)
    }

    private func loadDocuments(
        providerFingerprint: String,
        acceptedContentTypes: Set<XtreamContentType>
    ) async throws -> [SearchDocument] {
        try await persistence.loadDocuments(
            providerFingerprint: providerFingerprint,
            acceptedContentTypes: acceptedContentTypes
        )
    }

    private func loadIndexedCategories(
        scope: SearchMediaScope,
        providerFingerprint: String
    ) async throws -> Set<String> {
        try await persistence.loadIndexedCategories(
            scope: scope,
            providerFingerprint: providerFingerprint
        )
    }

    private func syncProgress(
        scope: SearchMediaScope,
        providerFingerprint: String
    ) async throws -> CatalogueSyncProgress {
        try await persistence.syncProgress(
            scope: scope,
            providerFingerprint: providerFingerprint
        )
    }

    private func refreshStates(providerFingerprint: String) async throws -> [String: RefreshStateSnapshot] {
        try await persistence.refreshStates(providerFingerprint: providerFingerprint)
    }

    private func recordCategoryRefreshAttempt(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String,
        at timestamp: Date
    ) async throws {
        try await persistence.recordCategoryRefreshAttempt(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID,
            at: timestamp
        )
    }

    private func recordCategoryRefreshSuccess(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String,
        at timestamp: Date
    ) async throws {
        try await persistence.recordCategoryRefreshSuccess(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID,
            at: timestamp
        )
        summaryCache[providerFingerprint] = nil
        await emitSyncProgressUpdates(
            providerFingerprint: providerFingerprint,
            affectedScopes: affectedScopes(for: contentType)
        )
    }

    private func recordCategoryRefreshFailure(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String,
        error: String,
        at timestamp: Date
    ) async throws {
        try await persistence.recordCategoryRefreshFailure(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID,
            error: error,
            at: timestamp
        )
    }

    private func deleteCategoryRefreshState(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String
    ) async throws {
        try await persistence.deleteCategoryRefreshState(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID
        )
    }

    private func removeAllRefreshStates(providerFingerprint: String) async throws {
        try await persistence.removeAllRefreshStates(providerFingerprint: providerFingerprint)
    }

    private func affectedScopes(for contentType: XtreamContentType) -> Set<SearchMediaScope> {
        switch contentType {
        case .vod:
            [.movies, .all]
        case .series:
            [.series, .all]
        case .live:
            []
        }
    }

    private func emitSyncProgressUpdates(
        providerFingerprint: String,
        affectedScopes: Set<SearchMediaScope>
    ) async {
        guard !affectedScopes.isEmpty else { return }

        let matchingObservers = syncObservers.filter { _, observer in
            observer.providerFingerprint == providerFingerprint && affectedScopes.contains(observer.scope)
        }
        guard !matchingObservers.isEmpty else { return }

        for scope in affectedScopes {
            guard let progress = try? await syncProgress(scope: scope, providerFingerprint: providerFingerprint) else {
                continue
            }

            for observer in matchingObservers.values where observer.scope == scope {
                observer.continuation.yield(progress)
            }
        }
    }

    private func removeSyncObserver(id: UUID) {
        syncObservers[id] = nil
    }

    private func matchesFilters(
        document: SearchDocument,
        filters: SearchFilters,
        normalizedGenreFilters: Set<String>,
        normalizedLanguageFilters: Set<String>,
        now: Date
    ) -> Bool {
        if let minRating = filters.minRating {
            guard let rating = document.rating, rating >= minRating else { return false }
        }
        if let maxRating = filters.maxRating {
            guard let rating = document.rating, rating <= maxRating else { return false }
        }
        if !normalizedGenreFilters.isEmpty && document.normalizedGenres.isDisjoint(with: normalizedGenreFilters) {
            return false
        }
        if !normalizedLanguageFilters.isEmpty {
            guard let language = document.normalizedLanguage,
                  normalizedLanguageFilters.contains(language) else { return false }
        }
        if !filters.categoryIDs.isEmpty && document.categoryIDs.isDisjoint(with: filters.categoryIDs) {
            return false
        }
        if let dayCount = filters.addedWindow.dayCount {
            guard let addedAt = document.addedAt,
                  let threshold = Calendar.current.date(byAdding: .day, value: -dayCount, to: now),
                  addedAt >= threshold else {
                return false
            }
        }
        return true
    }

    private func computeMatch(
        for document: SearchDocument,
        normalizedQuery: String,
        now: Date
    ) -> (score: Double, matchedFields: Set<SearchMatchedField>) {
        guard !normalizedQuery.isEmpty else {
            return (baseScore(for: document, now: now), [])
        }

        var matchedFields: Set<SearchMatchedField> = []
        var score = 0.0

        if document.normalizedTitle.hasPrefix(normalizedQuery) {
            matchedFields.insert(.titlePrefix)
            score += 100
        } else if document.normalizedTitle.contains(normalizedQuery) {
            matchedFields.insert(.titleContains)
            score += 50
        }

        var metadataHits = 0
        if document.normalizedGenres.contains(where: { $0.contains(normalizedQuery) }) {
            matchedFields.insert(.genre)
            metadataHits += 1
        }
        if document.normalizedCategoryNamesByID.values.contains(where: { $0.contains(normalizedQuery) }) {
            matchedFields.insert(.category)
            metadataHits += 1
        }
        if let language = document.normalizedLanguage, language.contains(normalizedQuery) {
            matchedFields.insert(.language)
            metadataHits += 1
        }

        score += Double(min(metadataHits, 2) * 20)
        score += baseScore(for: document, now: now)
        return (score, matchedFields)
    }

    private func baseScore(for document: SearchDocument, now: Date) -> Double {
        var score = 0.0
        if let rating = document.rating {
            score += min(max(rating / 10.0, 0), 1) * 10.0
        }
        if let addedAt = document.addedAt {
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
        let left = primary(lhs)
        let right = primary(rhs)
        if left != right {
            return descending ? left > right : left < right
        }
        let titleOrder = lhs.document.title.localizedCaseInsensitiveCompare(rhs.document.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.document.videoID < rhs.document.videoID
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from payload: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw NetworkError.invalidResponse
        }
    }

    private static func normalize(_ input: String) -> String {
        input
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func formatRating(_ rating: Double?) -> String? {
        guard let rating else { return nil }
        return rating.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
    }
}

@ModelActor
private actor CataloguePersistence {
    func loadStoredCategories(
        providerFingerprint: String,
        acceptedContentTypes: Set<String>
    ) throws -> [PersistedCategoryRecord] {
        try modelContext.fetch(
            FetchDescriptor<PersistedCategoryRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint },
                sortBy: [
                    SortDescriptor(\.contentType, order: .forward),
                    SortDescriptor(\.sortIndex, order: .forward)
                ]
            )
        ).filter { acceptedContentTypes.contains($0.contentType) }
    }

    func loadStoredStreamRecords(providerFingerprint: String) throws -> [PersistedStreamRecord] {
        try modelContext.fetch(
            FetchDescriptor<PersistedStreamRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )
    }

    func loadDocuments(
        providerFingerprint: String,
        acceptedContentTypes: Set<XtreamContentType>
    ) throws -> [CatalogueStore.SearchDocument] {
        let rawAcceptedContentTypes = Set(acceptedContentTypes.map(\.rawValue))
        let records = try loadStoredStreamRecords(providerFingerprint: providerFingerprint)
        var documentsByKey: [String: CatalogueStore.SearchDocument] = [:]
        documentsByKey.reserveCapacity(records.count)

        for record in records {
            guard let indexedContentType = XtreamContentType(rawValue: record.contentType),
                  rawAcceptedContentTypes.contains(indexedContentType.rawValue) else {
                continue
            }

            let key = "\(indexedContentType.rawValue):\(record.videoID)"
            var categoryNamesByID = documentsByKey[key]?.categoryNamesByID ?? [:]
            var normalizedCategoryNamesByID = documentsByKey[key]?.normalizedCategoryNamesByID ?? [:]
            categoryNamesByID[record.categoryID] = record.categoryName
            normalizedCategoryNamesByID[record.categoryID] = record.normalizedCategoryName

            documentsByKey[key] = CatalogueStore.SearchDocument(
                videoID: record.videoID,
                indexedContentType: indexedContentType,
                playbackContentType: record.playbackContentType,
                title: record.name,
                normalizedTitle: record.normalizedTitle,
                containerExtension: record.containerExtension,
                coverImageURL: record.coverImageURL,
                rating: record.rating,
                addedAtRaw: record.addedAtRaw,
                addedAt: record.addedAt,
                language: record.language,
                normalizedLanguage: record.normalizedLanguage,
                categoryNamesByID: categoryNamesByID,
                normalizedCategoryNamesByID: normalizedCategoryNamesByID
            )
        }

        return Array(documentsByKey.values)
    }

    func loadIndexedCategories(
        scope: SearchMediaScope,
        providerFingerprint: String
    ) throws -> Set<String> {
        let rawAcceptedContentTypes = Set(scope.acceptedContentTypes.map(\.rawValue))
        let records = try modelContext.fetch(
            FetchDescriptor<PersistedCategoryRefreshStateRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )
        return Set(
            records
                .filter { rawAcceptedContentTypes.contains($0.contentType) && $0.lastSuccessfulRefreshAt != nil }
                .map(\.categoryID)
        )
    }

    func syncProgress(
        scope: SearchMediaScope,
        providerFingerprint: String
    ) throws -> CatalogueSyncProgress {
        let syncedCategories = try loadIndexedCategories(
            scope: scope,
            providerFingerprint: providerFingerprint
        ).count
        let totalCategories = try loadStoredCategories(
            providerFingerprint: providerFingerprint,
            acceptedContentTypes: Set(scope.acceptedContentTypes.map(\.rawValue))
        ).count
        return CatalogueSyncProgress(
            syncedCategories: syncedCategories,
            totalCategories: totalCategories,
            scope: scope
        )
    }

    func refreshStates(providerFingerprint: String) throws -> [String: CatalogueStore.RefreshStateSnapshot] {
        let records = try modelContext.fetch(
            FetchDescriptor<PersistedCategoryRefreshStateRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )

        return Dictionary(
            uniqueKeysWithValues: records.compactMap { record in
                guard let contentType = XtreamContentType(rawValue: record.contentType) else { return nil }
                return (
                    "\(record.contentType):\(record.categoryID)",
                    CatalogueStore.RefreshStateSnapshot(
                        contentType: contentType,
                        categoryID: record.categoryID,
                        lastSuccessfulRefreshAt: record.lastSuccessfulRefreshAt,
                        nextEligibleRefreshAt: record.nextEligibleRefreshAt
                    )
                )
            }
        )
    }

    func recordCategoryRefreshAttempt(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String,
        at timestamp: Date
    ) throws {
        if let record = try refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID
        ) {
            record.lastAttemptedRefreshAt = timestamp
        } else {
            modelContext.insert(
                PersistedCategoryRefreshStateRecord(
                    id: "\(providerFingerprint)|\(contentType.rawValue)|\(categoryID)",
                    providerFingerprint: providerFingerprint,
                    contentType: contentType.rawValue,
                    categoryID: categoryID,
                    lastSuccessfulRefreshAt: nil,
                    lastAttemptedRefreshAt: timestamp,
                    nextEligibleRefreshAt: nil,
                    failureCount: 0,
                    lastError: nil
                )
            )
        }
        try modelContext.save()
    }

    func recordCategoryRefreshSuccess(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String,
        at timestamp: Date
    ) throws {
        let record = try refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID
        ) ?? PersistedCategoryRefreshStateRecord(
            id: "\(providerFingerprint)|\(contentType.rawValue)|\(categoryID)",
            providerFingerprint: providerFingerprint,
            contentType: contentType.rawValue,
            categoryID: categoryID,
            lastSuccessfulRefreshAt: nil,
            lastAttemptedRefreshAt: nil,
            nextEligibleRefreshAt: nil,
            failureCount: 0,
            lastError: nil
        )

        if try refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID
        ) == nil {
            modelContext.insert(record)
        }

        record.lastSuccessfulRefreshAt = timestamp
        record.lastAttemptedRefreshAt = timestamp
        record.nextEligibleRefreshAt = timestamp.addingTimeInterval(30 * 60)
        record.failureCount = 0
        record.lastError = nil
        try modelContext.save()
    }

    func recordCategoryRefreshFailure(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String,
        error: String,
        at timestamp: Date
    ) throws {
        let record = try refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID
        ) ?? PersistedCategoryRefreshStateRecord(
            id: "\(providerFingerprint)|\(contentType.rawValue)|\(categoryID)",
            providerFingerprint: providerFingerprint,
            contentType: contentType.rawValue,
            categoryID: categoryID,
            lastSuccessfulRefreshAt: nil,
            lastAttemptedRefreshAt: nil,
            nextEligibleRefreshAt: nil,
            failureCount: 0,
            lastError: nil
        )

        if try refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID
        ) == nil {
            modelContext.insert(record)
        }

        record.lastAttemptedRefreshAt = timestamp
        record.failureCount += 1
        record.lastError = error
        let backoff = min(30 * 60.0, 2 * 60.0 * pow(2.0, Double(max(0, record.failureCount - 1))))
        record.nextEligibleRefreshAt = timestamp.addingTimeInterval(backoff)
        try modelContext.save()
    }

    func deleteCategoryRefreshState(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String
    ) throws {
        guard let record = try refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID
        ) else {
            return
        }

        modelContext.delete(record)
        try modelContext.save()
    }

    func removeAllRefreshStates(providerFingerprint: String) throws {
        try modelContext.delete(
            model: PersistedCategoryRefreshStateRecord.self,
            where: #Predicate { $0.providerFingerprint == providerFingerprint }
        )
        try modelContext.save()
    }

    private func refreshStateRecord(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String
    ) throws -> PersistedCategoryRefreshStateRecord? {
        let rawContentType = contentType.rawValue
        return try modelContext.fetch(
            FetchDescriptor<PersistedCategoryRefreshStateRecord>(
                predicate: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.contentType == rawContentType &&
                    $0.categoryID == categoryID
                }
            )
        ).first
    }
}
