//
//  Catalog.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
//

import Foundation
import SwiftData

enum CatalogError: LocalizedError {
    case missingProviderConfiguration
    case cacheUnavailable

    var errorDescription: String? {
        switch self {
        case .missingProviderConfiguration:
            "Configure your provider in Settings before loading content."
        case .cacheUnavailable:
            "No cached content is available yet."
        }
    }
}

@MainActor
@Observable
final class Catalog {
    private struct ProviderState {
        let revision: Int
        let config: ProviderConfig
        let fingerprint: String
    }

    private struct CategoryTaskKey: Hashable {
        let providerFingerprint: String
        let contentType: XtreamContentType
        let categoryID: String
    }

    private struct RefreshStateSnapshot {
        let contentType: XtreamContentType
        let categoryID: String
        let lastSuccessfulRefreshAt: Date?
        let lastAttemptedRefreshAt: Date?
        let nextEligibleRefreshAt: Date?
        let failureCount: Int
        let lastError: String?
    }

    var vodCategories: [Category] = []
    var seriesCategories: [Category] = []

    var vodCatalog: [Category: [Video]] = [:]
    var seriesCatalog: [Category: [Video]] = [:]
    var liveCatalog: [Category: [Video]] = [:]

    var vodInfo: [Video: VideoInfo] = [:]
    var catalogueRevision = 0

    private var seriesInfoBySeriesID: [Int: XtreamSeries] = [:]
    private var providerRevision: Int
    private var cachedProviderState: ProviderState?
    private var inFlightStreamLoads: [CategoryTaskKey: Task<[CachedVideoDTO], Error>] = [:]

    private let providerStore: ProviderStore
    private let modelContainer: ModelContainer
    private let cacheManager: CatalogCacheManager
    private let metadataCacheManager: CatalogMetadataCacheManager
    private let imagePrefetcher: ImagePrefetching
    private let store: CatalogueStore
    private let backgroundRefresher: BackgroundCatalogueRefresher

    let activityCenter: BackgroundActivityCenter

    init(
        providerStore: ProviderStore,
        modelContainer: ModelContainer,
        cacheManager: CatalogCacheManager? = nil,
        metadataCacheManager: CatalogMetadataCacheManager? = nil,
        imagePrefetcher: ImagePrefetching? = nil,
        activityCenter: BackgroundActivityCenter? = nil,
        backgroundCatalogueRefresher: BackgroundCatalogueRefresher? = nil
    ) {
        self.providerStore = providerStore
        self.modelContainer = modelContainer
        self.cacheManager = cacheManager ?? CatalogCacheManager(
            diskStore: SwiftDataStreamListCacheStore(modelContainer: modelContainer)
        )
        self.metadataCacheManager = metadataCacheManager ?? CatalogMetadataCacheManager(
            diskStore: SwiftDataCatalogMetadataCacheStore(modelContainer: modelContainer)
        )
        self.imagePrefetcher = imagePrefetcher ?? NoopImagePrefetcher()
        self.store = CatalogueStore(
            providerStore: providerStore,
            modelContainer: modelContainer,
            cacheManager: self.cacheManager,
            metadataCacheManager: self.metadataCacheManager
        )
        self.activityCenter = activityCenter ?? BackgroundActivityCenter()
        self.backgroundRefresher = backgroundCatalogueRefresher ?? BackgroundCatalogueRefresher()
        self.providerRevision = providerStore.revision
    }

    var hasProviderConfiguration: Bool {
        providerStore.hasConfiguration
    }

    func cachedSeriesInfo(for video: Video) -> XtreamSeries? {
        seriesInfoBySeriesID[video.id]
    }

    func reset() {
        vodCategories = []
        seriesCategories = []
        vodCatalog = [:]
        seriesCatalog = [:]
        liveCatalog = [:]
        vodInfo = [:]
        seriesInfoBySeriesID = [:]
        cachedProviderState = nil
        inFlightStreamLoads.values.forEach { $0.cancel() }
        inFlightStreamLoads.removeAll()
        catalogueRevision += 1

        Task(priority: .utility) {
            await self.store.resetTransientState()
            await self.backgroundRefresher.stop()
        }
    }

    func prefetchImages(urls: [URL]) async {
        await imagePrefetcher.prefetch(urls: urls)
    }

    func startBackgroundRefreshing() async {
        guard hasProviderConfiguration, let fingerprint = try? currentProviderFingerprint() else {
            await backgroundRefresher.stop()
            return
        }

        await backgroundRefresher.start(
            providerFingerprint: fingerprint,
            ensureBootstrap: { [weak self] in
                guard let self else { throw CancellationError() }
                _ = try await self.store.bootstrap(providerFingerprint: fingerprint)
            },
            nextTarget: { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.store.nextRefreshCandidate()
            },
            refresh: { [weak self] target in
                guard let self else { throw CancellationError() }
                try await self.store.refreshCategory(target)
            },
            progress: { [weak self] scope, providerFingerprint in
                guard let self else {
                    return CatalogueSyncProgress(syncedCategories: 0, totalCategories: 0, scope: scope)
                }
                return (try? await self.store.syncProgress(scope: scope))
                    ?? CatalogueSyncProgress(syncedCategories: 0, totalCategories: 0, scope: scope)
            }
        )
    }

    func stopBackgroundRefreshing() async {
        await backgroundRefresher.stop()
    }

    private func ensureCurrentProvider() {
        guard providerRevision != providerStore.revision else { return }
        providerRevision = providerStore.revision
        reset()
    }

    private func providerState() throws -> ProviderState {
        ensureCurrentProvider()

        if let cachedProviderState, cachedProviderState.revision == providerStore.revision {
            return cachedProviderState
        }

        let config = try providerStore.requiredConfiguration()
        let state = ProviderState(
            revision: providerStore.revision,
            config: config,
            fingerprint: ProviderCacheFingerprint.make(from: config)
        )
        cachedProviderState = state
        return state
    }

    private func currentProviderFingerprint() throws -> String {
        try providerState().fingerprint
    }

    private func service() throws -> XtreamService {
        let state = try providerState()
        return XtreamService(
            .shared,
            baseURL: state.config.apiURL,
            username: state.config.username,
            password: state.config.password
        )
    }

    private func cacheKey(for category: Category, contentType: XtreamContentType) throws -> StreamListCacheKey {
        let state = try providerState()
        return StreamListCacheKey(
            providerFingerprint: state.fingerprint,
            contentType: contentType,
            categoryID: category.id,
            pageToken: nil
        )
    }

    private func metadataKey(kind: CatalogMetadataKind, resourceID: String) throws -> CatalogMetadataCacheKey {
        CatalogMetadataCacheKey(
            providerFingerprint: try currentProviderFingerprint(),
            kind: kind,
            resourceID: resourceID
        )
    }

    private func cacheOnlyFailure(policy: CatalogLoadPolicy, fallbackError: Error? = nil) throws -> Never {
        if case .cacheOnly = policy, let fallbackError {
            throw fallbackError
        }
        throw fallbackError ?? CatalogError.cacheUnavailable
    }

    private func decodeCachedValue<Value: Decodable>(_ type: Value.Type, from payload: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: payload)
        } catch {
            throw NetworkError.invalidResponse
        }
    }

    private func applyCategoryVisibility(to categories: [Category]) -> [Category] {
        categories.filter { !providerStore.isExcludedCategoryPrefix($0.languageGroupCode) }
    }

    private func applyCategories(_ categories: [CachedCategoryDTO], for contentType: XtreamContentType) {
        let visible = applyCategoryVisibility(to: categories.map(Category.init(cached:)))
        switch contentType {
        case .vod:
            vodCategories = visible
            vodCatalog = reboundCatalogStorage(vodCatalog, to: visible)
        case .series:
            seriesCategories = visible
            seriesCatalog = reboundCatalogStorage(seriesCatalog, to: visible)
        case .live:
            break
        }
        catalogueRevision += 1
    }

    private func applyStreams(_ videos: [CachedVideoDTO], in category: Category, contentType: XtreamContentType) {
        let mapped = videos.map(Video.init)
        switch contentType {
        case .vod:
            removeCachedStreams(categoryID: category.id, contentType: .vod)
            vodCatalog[category] = mapped
        case .series:
            removeCachedStreams(categoryID: category.id, contentType: .series)
            seriesCatalog[category] = mapped
        case .live:
            removeCachedStreams(categoryID: category.id, contentType: .live)
            liveCatalog[category] = mapped
        }
        catalogueRevision += 1
    }

    private func reboundCatalogStorage(
        _ storage: [Category: [Video]],
        to categories: [Category]
    ) -> [Category: [Video]] {
        var rebound: [Category: [Video]] = [:]

        for category in categories {
            guard let entry = storage.first(where: { $0.key.id == category.id }) else { continue }
            rebound[category] = entry.value
        }

        return rebound
    }

    private func removeCachedStreams(categoryID: String, contentType: XtreamContentType) {
        switch contentType {
        case .vod:
            vodCatalog = vodCatalog.filter { $0.key.id != categoryID }
        case .series:
            seriesCatalog = seriesCatalog.filter { $0.key.id != categoryID }
        case .live:
            liveCatalog = liveCatalog.filter { $0.key.id != categoryID }
        }
    }

    private func cachedVideosByID(categoryID: String, contentType: XtreamContentType) -> [Video]? {
        switch contentType {
        case .vod:
            vodCatalog.first { $0.key.id == categoryID }?.value
        case .series:
            seriesCatalog.first { $0.key.id == categoryID }?.value
        case .live:
            liveCatalog.first { $0.key.id == categoryID }?.value
        }
    }

    private func ensureBootstrapCategoriesLoaded() async throws {
        try await getVodCategories(policy: .readThrough)
        try await getSeriesCategories(policy: .readThrough)
    }

}

extension Catalog {
    func getVodCategories(force: Bool = false) async throws {
        try await getVodCategories(policy: force ? .forceRefresh : .readThrough)
    }

    func getSeriesCategories(force: Bool = false) async throws {
        try await getSeriesCategories(policy: force ? .forceRefresh : .readThrough)
    }

    func getVodStreams(in category: Category, force: Bool = false) async throws {
        try await getVodStreams(in: category, policy: force ? .forceRefresh : .readThrough)
    }

    func getSeriesStreams(in category: Category, force: Bool = false) async throws {
        try await getSeriesStreams(in: category, policy: force ? .forceRefresh : .readThrough)
    }

    func getVodInfo(_ video: Video, force: Bool = false) async throws {
        try await getVodInfo(video, policy: force ? .forceRefresh : .readThrough)
    }

    func getSeriesInfo(_ video: Video, force: Bool = false) async throws -> XtreamSeries {
        try await getSeriesInfo(video, policy: force ? .forceRefresh : .readThrough)
    }

    func resolveURL(for video: Video) throws -> URL {
        try service().getPlayURL(for: video.id, type: video.contentType, containerExtension: video.containerExtension)
    }

    func resolveEpisodeDownloadURL(
        seriesID: Int,
        episodeVideoID: Int,
        containerExtension: String,
        directSource: String
    ) throws -> URL {
        let normalizedDirectSource = directSource.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedDirectSource.isEmpty, let directURL = URL(string: normalizedDirectSource) {
            return directURL
        }

        return try service().getPlayURL(
            for: episodeVideoID,
            type: XtreamContentType.series.rawValue,
            containerExtension: containerExtension
        )
    }

    func prepareDownloadMetadata(for video: Video) async throws -> DownloadPreparedMetadata {
        switch video.xtreamContentType {
        case .vod:
            try await getVodInfo(video, policy: .readThrough)
            let resolvedInfo = vodInfo[video] ?? VideoInfo(
                images: [],
                plot: "",
                cast: "",
                director: "",
                genre: "",
                releaseDate: "",
                durationLabel: "",
                runtimeMinutes: nil,
                ageRating: "",
                country: "",
                rating: video.rating
            )

            let artworkURLs = Array(
                Set(
                    resolvedInfo.images +
                    [video.coverImageURL].compactMap { $0 }.compactMap(URL.init(string:))
                )
            )

            return DownloadPreparedMetadata(
                snapshotID: DownloadIdentifiers.metadataSnapshotID(
                    scope: DownloadScope(
                        profileID: "primary",
                        providerFingerprint: try currentProviderFingerprint()
                    ),
                    contentType: video.contentType,
                    videoID: video.id
                ),
                kind: .movie,
                videoID: video.id,
                contentType: video.contentType,
                title: video.name,
                coverImageURL: video.coverImageURL,
                artworkURLs: artworkURLs,
                movieInfo: CachedVideoInfoDTO(resolvedInfo),
                seriesInfo: nil
            )

        case .series:
            let seriesInfo = try await getSeriesInfo(video, policy: .readThrough)
            let artworkURLs = Array(
                Set(
                    [
                        seriesInfo.info.backdropPath.first,
                        seriesInfo.info.cover,
                        video.coverImageURL
                    ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .compactMap(URL.init(string:)) +
                    seriesInfo.episodes.values
                        .flatMap { $0 }
                        .compactMap { episode in
                            let value = episode.info.movieImage.trimmingCharacters(in: .whitespacesAndNewlines)
                            return value.isEmpty ? nil : URL(string: value)
                        }
                )
            )

            return DownloadPreparedMetadata(
                snapshotID: DownloadIdentifiers.metadataSnapshotID(
                    scope: DownloadScope(
                        profileID: "primary",
                        providerFingerprint: try currentProviderFingerprint()
                    ),
                    contentType: video.contentType,
                    videoID: video.id
                ),
                kind: .series,
                videoID: video.id,
                contentType: video.contentType,
                title: seriesInfo.info.name.isEmpty ? video.name : seriesInfo.info.name,
                coverImageURL: video.coverImageURL,
                artworkURLs: artworkURLs,
                movieInfo: nil,
                seriesInfo: seriesInfo
            )

        case .live:
            throw DownloadRuntimeError.unsupportedContent
        }
    }

    func search(_ query: SearchQuery) async throws -> [SearchResultItem] {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        return try await store.search(query)
    }

    func searchFacetValues(scope: SearchMediaScope) async throws -> SearchFacetValues {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        return try await store.facetValues(scope: scope)
    }

    func syncProgress(scope: SearchMediaScope) async throws -> CatalogueSyncProgress {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        return try await store.syncProgress(scope: scope)
    }

    func providerCatalogueSummary() async throws -> ProviderCatalogueSummary {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        return try await store.providerCatalogueSummary()
    }

    func runBackgroundCatalogueIndex(forceRefresh: Bool = false) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        let fingerprint = try currentProviderFingerprint()

        if forceRefresh {
            try await getVodCategories(policy: .forceRefresh)
            try await getSeriesCategories(policy: .forceRefresh)
        } else {
            try await ensureBootstrapCategoriesLoaded()
        }

        let targets: [BackgroundCatalogueRefreshTarget]
        if forceRefresh {
            targets = vodCategories.enumerated().map {
                BackgroundCatalogueRefreshTarget(
                    providerFingerprint: fingerprint,
                    contentType: .vod,
                    categoryID: $0.element.id,
                    categoryName: $0.element.name,
                    sortIndex: $0.offset
                )
            } + seriesCategories.enumerated().map {
                BackgroundCatalogueRefreshTarget(
                    providerFingerprint: fingerprint,
                    contentType: .series,
                    categoryID: $0.element.id,
                    categoryName: $0.element.name,
                    sortIndex: $0.offset
                )
            }
        } else if let next = try await store.nextRefreshCandidate() {
            targets = [next]
        } else {
            targets = []
        }

        guard !targets.isEmpty else {
            activityCenter.finish(id: "background-refresh:\(fingerprint)", detail: "Up to date")
            return
        }

        let activityID = "background-refresh:\(fingerprint)"
        activityCenter.start(
            id: activityID,
            title: "Refreshing Catalogue",
            detail: nil,
            source: "Library",
            progress: (0, max(targets.count, 1))
        )

        do {
            for (index, target) in targets.enumerated() {
                try await activityCenter.waitIfResumed()
                try await store.refreshCategory(target)
                activityCenter.update(
                    id: activityID,
                    detail: target.categoryName,
                    progress: (index + 1, max(targets.count, 1))
                )
            }
            activityCenter.finish(id: activityID, detail: "Up to date")
        } catch is CancellationError {
            activityCenter.cancel(id: activityID)
            throw CancellationError()
        } catch {
            activityCenter.fail(id: activityID, error: error)
            throw error
        }
    }

    func observeSyncProgress(scope: SearchMediaScope) -> AsyncStream<CatalogueSyncProgress> {
        AsyncStream { continuation in
            Task { @MainActor in
                guard hasProviderConfiguration else {
                    continuation.yield(CatalogueSyncProgress(syncedCategories: 0, totalCategories: 0, scope: scope))
                    continuation.finish()
                    return
                }

                await startBackgroundRefreshing()
                let providerFingerprint = (try? currentProviderFingerprint()) ?? ""
                let stream = await backgroundRefresher.observeProgress(
                    scope: scope,
                    providerFingerprint: providerFingerprint
                ) { [weak self] scope, providerFingerprint in
                    guard let self else {
                        return CatalogueSyncProgress(syncedCategories: 0, totalCategories: 0, scope: scope)
                    }
                    return (try? await self.store.syncProgress(scope: scope))
                        ?? CatalogueSyncProgress(syncedCategories: 0, totalCategories: 0, scope: scope)
                }

                for await progress in stream {
                    continuation.yield(progress)
                }

                continuation.finish()
            }
        }
    }

    func clearSearchIndex() async {
        catalogueRevision += 1
    }

    func ensureBootstrapLoaded() async throws {
        _ = try await store.bootstrap(providerFingerprint: try currentProviderFingerprint())
    }

    func getVodCategories(policy: CatalogLoadPolicy = .readThrough) async throws {
        let categories = try await store.loadCategories(contentType: .vod, policy: policy)
        applyCategories(categories, for: .vod)
    }

    func getSeriesCategories(policy: CatalogLoadPolicy = .readThrough) async throws {
        let categories = try await store.loadCategories(contentType: .series, policy: policy)
        applyCategories(categories, for: .series)
    }

    func getVodStreams(in category: Category, policy: CatalogLoadPolicy = .readThrough) async throws {
        let videos = try await store.loadCategory(
            contentType: .vod,
            categoryID: category.id,
            categoryName: category.name,
            policy: policy,
            reason: .userVisible
        )
        applyStreams(videos, in: category, contentType: .vod)
    }

    func getSeriesStreams(in category: Category, policy: CatalogLoadPolicy = .readThrough) async throws {
        let videos = try await store.loadCategory(
            contentType: .series,
            categoryID: category.id,
            categoryName: category.name,
            policy: policy,
            reason: .userVisible
        )
        applyStreams(videos, in: category, contentType: .series)
    }

    func getVodInfo(_ video: Video, policy: CatalogLoadPolicy = .readThrough) async throws {
        let info = try await store.loadMovieInfo(video: video, policy: policy, reason: .userVisible)
        vodInfo[video] = VideoInfo(cached: info)
    }

    func getSeriesInfo(_ video: Video, policy: CatalogLoadPolicy = .readThrough) async throws -> XtreamSeries {
        let info = try await store.loadSeriesInfo(video: video, policy: policy, reason: .userVisible)
        seriesInfoBySeriesID[video.id] = info
        return info
    }

    func clearProviderCaches() async throws {
        try await store.clearAllCaches()
        reset()
    }

    func clearMediaCache() {
        URLCache.shared.removeAllCachedResponses()
    }

    func rebuildSearchIndexFromCachedMetadata() async throws {
        catalogueRevision += 1
    }

    func refreshCurrentProvider() async throws {
        try await getVodCategories(policy: .forceRefresh)
        try await getSeriesCategories(policy: .forceRefresh)
    }

    func categories(for contentType: XtreamContentType) -> [Category] {
        switch contentType {
        case .vod:
            vodCategories
        case .series:
            seriesCategories
        case .live:
            []
        }
    }

    func cachedVideos(in category: Category, contentType: XtreamContentType) -> [Video]? {
        cachedVideosByID(categoryID: category.id, contentType: contentType)
    }

    func getCategories(for contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws {
        switch contentType {
        case .vod:
            try await getVodCategories(policy: policy)
        case .series:
            try await getSeriesCategories(policy: policy)
        case .live:
            break
        }
    }

    func getCategories(for contentType: XtreamContentType, force: Bool = false) async throws {
        try await getCategories(for: contentType, policy: force ? .forceRefresh : .readThrough)
    }

    func getStreams(in category: Category, contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws {
        switch contentType {
        case .vod:
            try await getVodStreams(in: category, policy: policy)
        case .series:
            try await getSeriesStreams(in: category, policy: policy)
        case .live:
            break
        }
    }

    func getStreams(in category: Category, contentType: XtreamContentType, force: Bool = false) async throws {
        try await getStreams(in: category, contentType: contentType, policy: force ? .forceRefresh : .readThrough)
    }
}
