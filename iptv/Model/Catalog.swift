//
//  Catalog.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
//

import Foundation
import SwiftData
import OSLog

enum CatalogError: LocalizedError {
    case missingProviderConfiguration
    case cacheUnavailable

    var errorDescription: String? {
        switch self {
        case .missingProviderConfiguration:
            return "Configure your provider in Settings before loading content."
        case .cacheUnavailable:
            return "No cached content is available yet."
        }
    }
}

@MainActor
@Observable
final class Catalog {
    var vodCategories: [Category] = []
    var seriesCategories: [Category] = []

    var vodCatalog: [Category: [Video]] = [:]
    var seriesCatalog: [Category: [Video]] = [:]
    var liveCatalog: [Category: [Video]] = [:]

    var vodInfo: [Video: VideoInfo] = [:]
    private var seriesInfoBySeriesID: [Int: XtreamSeries] = [:]

    private let providerStore: ProviderStore
    private let cacheManager: CatalogCacheManager
    private let metadataCacheManager: CatalogMetadataCacheManager
    private let imagePrefetcher: ImagePrefetching
    private let searchIndexStore: SearchIndexStore
    private let searchOrchestrator: SearchOrchestrator
    let activityCenter: BackgroundActivityCenter

    private var providerRevision: Int

    init(
        providerStore: ProviderStore,
        modelContainer: ModelContainer,
        cacheManager: CatalogCacheManager? = nil,
        metadataCacheManager: CatalogMetadataCacheManager? = nil,
        imagePrefetcher: ImagePrefetching? = nil,
        searchIndexStore: SearchIndexStore? = nil,
        searchOrchestrator: SearchOrchestrator? = nil,
        activityCenter: BackgroundActivityCenter? = nil
    ) {
        self.providerStore = providerStore
        self.cacheManager = cacheManager ?? CatalogCacheManager()
        self.metadataCacheManager = metadataCacheManager ?? CatalogMetadataCacheManager()
        self.imagePrefetcher = imagePrefetcher ?? NoopImagePrefetcher()
        self.searchIndexStore = searchIndexStore ?? SearchIndexStore()
        self.searchOrchestrator = searchOrchestrator ?? SearchOrchestrator()
        self.activityCenter = activityCenter ?? BackgroundActivityCenter()
        _ = modelContainer
        self.providerRevision = providerStore.revision
    }

    var hasProviderConfiguration: Bool {
        providerStore.hasConfiguration
    }

    func reset() {
        vodCategories = []
        seriesCategories = []
        vodCatalog = [:]
        seriesCatalog = [:]
        liveCatalog = [:]
        vodInfo = [:]
        seriesInfoBySeriesID = [:]
        Task(priority: .utility) {
            await cacheManager.clearMemoryCache()
            await metadataCacheManager.clearMemoryCache()
            await searchIndexStore.clearAll()
            searchOrchestrator.cancelAll()
        }
    }

    func prefetchImages(urls: [URL]) async {
        await imagePrefetcher.prefetch(urls: urls)
    }

    private func ensureCurrentProvider() {
        guard providerRevision != providerStore.revision else { return }
        providerRevision = providerStore.revision
        reset()
    }

    private func currentProviderFingerprint() throws -> String {
        ensureCurrentProvider()
        let config = try providerStore.requiredConfiguration()
        return ProviderCacheFingerprint.make(from: config)
    }

    private func service() throws -> XtreamService {
        ensureCurrentProvider()
        let config = try providerStore.requiredConfiguration()
        return XtreamService(
            .shared,
            baseURL: config.apiURL,
            username: config.username,
            password: config.password
        )
    }

    private func cacheKey(for category: Category, contentType: XtreamContentType) throws -> StreamListCacheKey {
        let config = try providerStore.requiredConfiguration()
        return StreamListCacheKey(
            providerFingerprint: ProviderCacheFingerprint.make(from: config),
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

    private func cachedOnlyFailure(
        policy: CatalogLoadPolicy,
        fallbackError: Error? = nil
    ) throws -> Never {
        if case .cachedOnly = policy, let fallbackError {
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
        case .series:
            seriesCategories = visible
        case .live:
            break
        }
    }

    private func applyStreams(_ videos: [CachedVideoDTO], in category: Category, contentType: XtreamContentType) {
        let mapped = videos.map(Video.init)
        switch contentType {
        case .vod:
            vodCatalog[category] = mapped
        case .series:
            seriesCatalog[category] = mapped
        case .live:
            liveCatalog[category] = mapped
        }
    }

    private func storeSearchSnapshots(
        from videos: [CachedVideoDTO],
        contentType: XtreamContentType,
        category: Category,
        providerFingerprint: String
    ) async {
        let snapshots = videos.map(SearchVideoSnapshot.init(cachedVideo:))
        await searchIndexStore.upsert(
            videos: snapshots,
            contentType: contentType,
            categoryID: category.id,
            categoryName: category.name,
            providerFingerprint: providerFingerprint
        )
    }

    private func fetchCategoryDTOs(for contentType: XtreamContentType) async throws -> [CachedCategoryDTO] {
        let dto = try await service().getCategories(of: contentType)
        return dto.map(CachedCategoryDTO.init)
    }

    private func fetchVodStreamDTOs(inCategoryID categoryID: String) async throws -> [CachedVideoDTO] {
        let service = try self.service()
        let streams = try await service.getStreams(of: .vod, in: categoryID)
        return streams.map(CachedVideoDTO.init)
    }

    private func fetchSeriesStreamDTOs(inCategoryID categoryID: String) async throws -> [CachedVideoDTO] {
        let service = try self.service()
        let series = try await service.getSeries(in: categoryID)
        return series.map(CachedVideoDTO.init)
    }

    private func runBackgroundActivity(
        id: String,
        title: String,
        detail: String,
        source: String,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }

            self.activityCenter.start(id: id, title: title, detail: detail, source: source)

            do {
                try await self.activityCenter.waitIfResumed()
                try await operation()
                self.activityCenter.finish(id: id)
            } catch is CancellationError {
                self.activityCenter.cancel(id: id)
            } catch {
                self.activityCenter.fail(id: id, error: error)
            }
        }
    }

    private func loadCategories(
        contentType: XtreamContentType,
        kind: CatalogMetadataKind,
        policy: CatalogLoadPolicy
    ) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }

        let key = try metadataKey(kind: kind, resourceID: "all")
        let cachedPayload = try await metadataCacheManager.cachedPayload(
            for: key,
            ttl: CatalogCacheTTL.categories
        )
        let cached = try cachedPayload.map {
            CatalogCachedValue(
                value: try decodeCachedValue([CachedCategoryDTO].self, from: $0.value),
                savedAt: $0.savedAt,
                isStale: $0.isStale
            )
        }

        switch policy {
        case .cachedOnly:
            guard let cached else { try cachedOnlyFailure(policy: policy) }
            applyCategories(cached.value, for: contentType)
        case .cachedThenRefresh:
            if let cached {
                applyCategories(cached.value, for: contentType)
                scheduleCategoryRefresh(key: key, kind: kind, contentType: contentType)
            } else {
                let fresh = try await refreshCategories(key: key, kind: kind, contentType: contentType)
                applyCategories(fresh, for: contentType)
            }
        case .refreshIfStale:
            if let cached {
                applyCategories(cached.value, for: contentType)
                if cached.isStale {
                    scheduleCategoryRefresh(key: key, kind: kind, contentType: contentType)
                }
            } else {
                let fresh = try await refreshCategories(key: key, kind: kind, contentType: contentType)
                applyCategories(fresh, for: contentType)
            }
        case .refreshNow:
            let fresh = try await refreshCategories(key: key, kind: kind, contentType: contentType)
            applyCategories(fresh, for: contentType)
        }
    }

    private func refreshCategories(
        key: CatalogMetadataCacheKey,
        kind: CatalogMetadataKind,
        contentType: XtreamContentType
    ) async throws -> [CachedCategoryDTO] {
        let fresh = try await metadataCacheManager.refreshPayload(
            for: key
        ) { [weak self] in
            guard let self else { throw CancellationError() }
            let value = try await self.fetchCategoryDTOs(for: contentType)
            return try JSONEncoder().encode(value)
        }
        let decoded = try decodeCachedValue([CachedCategoryDTO].self, from: fresh)
        applyCategories(decoded, for: contentType)
        return decoded
    }

    private func scheduleCategoryRefresh(
        key: CatalogMetadataCacheKey,
        kind: CatalogMetadataKind,
        contentType: XtreamContentType
    ) {
        runBackgroundActivity(
            id: "category-refresh:\(key.rawKey)",
            title: "Refreshing Categories",
            detail: "Updating \(contentType.rawValue) categories",
            source: "Catalog"
        ) { [weak self] in
            guard let self else { return }
            _ = try await self.refreshCategories(key: key, kind: kind, contentType: contentType)
        }
    }

    private func loadStreams(
        in category: Category,
        contentType: XtreamContentType,
        policy: CatalogLoadPolicy,
        fetcher: @escaping @Sendable () async throws -> [CachedVideoDTO]
    ) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }

        let key = try cacheKey(for: category, contentType: contentType)
        let providerFingerprint = key.providerFingerprint
        let cached = try await cacheManager.cachedValue(for: key, ttl: CatalogCacheTTL.streams)

        switch policy {
        case .cachedOnly:
            guard let cached else { try cachedOnlyFailure(policy: policy) }
            applyStreams(cached.value, in: category, contentType: contentType)
            await storeSearchSnapshots(from: cached.value, contentType: contentType, category: category, providerFingerprint: providerFingerprint)
        case .cachedThenRefresh:
            if let cached {
                applyStreams(cached.value, in: category, contentType: contentType)
                await storeSearchSnapshots(from: cached.value, contentType: contentType, category: category, providerFingerprint: providerFingerprint)
                scheduleStreamRefresh(for: key, category: category, contentType: contentType, fetcher: fetcher)
            } else {
                let fresh = try await refreshStreams(for: key, category: category, contentType: contentType, fetcher: fetcher)
                applyStreams(fresh, in: category, contentType: contentType)
            }
        case .refreshIfStale:
            if let cached {
                applyStreams(cached.value, in: category, contentType: contentType)
                await storeSearchSnapshots(from: cached.value, contentType: contentType, category: category, providerFingerprint: providerFingerprint)
                if cached.isStale {
                    scheduleStreamRefresh(for: key, category: category, contentType: contentType, fetcher: fetcher)
                }
            } else {
                let fresh = try await refreshStreams(for: key, category: category, contentType: contentType, fetcher: fetcher)
                applyStreams(fresh, in: category, contentType: contentType)
            }
        case .refreshNow:
            let fresh = try await refreshStreams(for: key, category: category, contentType: contentType, fetcher: fetcher)
            applyStreams(fresh, in: category, contentType: contentType)
        }
    }

    private func refreshStreams(
        for key: StreamListCacheKey,
        category: Category,
        contentType: XtreamContentType,
        fetcher: @escaping @Sendable () async throws -> [CachedVideoDTO]
    ) async throws -> [CachedVideoDTO] {
        let fresh = try await cacheManager.refreshValue(for: key, fetcher: fetcher)
        applyStreams(fresh, in: category, contentType: contentType)
        await storeSearchSnapshots(from: fresh, contentType: contentType, category: category, providerFingerprint: key.providerFingerprint)
        return fresh
    }

    private func scheduleStreamRefresh(
        for key: StreamListCacheKey,
        category: Category,
        contentType: XtreamContentType,
        fetcher: @escaping @Sendable () async throws -> [CachedVideoDTO]
    ) {
        runBackgroundActivity(
            id: "stream-refresh:\(key.rawKey)",
            title: "Refreshing Library",
            detail: "\(category.name)",
            source: "Catalog"
        ) { [weak self] in
            guard let self else { return }
            _ = try await self.refreshStreams(for: key, category: category, contentType: contentType, fetcher: fetcher)
        }
    }

    private func loadVodInfo(
        _ video: Video,
        policy: CatalogLoadPolicy
    ) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }

        let key = try metadataKey(kind: .vodInfo, resourceID: String(video.id))
        let cachedPayload = try await metadataCacheManager.cachedPayload(
            for: key,
            ttl: CatalogCacheTTL.details
        )
        let cached = try cachedPayload.map {
            CatalogCachedValue(
                value: try decodeCachedValue(CachedVideoInfoDTO.self, from: $0.value),
                savedAt: $0.savedAt,
                isStale: $0.isStale
            )
        }

        switch policy {
        case .cachedOnly:
            guard let cached else { try cachedOnlyFailure(policy: policy) }
            vodInfo[video] = VideoInfo(cached: cached.value)
        case .cachedThenRefresh:
            if let cached {
                vodInfo[video] = VideoInfo(cached: cached.value)
                scheduleVodInfoRefresh(video, key: key)
            } else {
                let fresh = try await refreshVodInfo(video, key: key)
                vodInfo[video] = VideoInfo(cached: fresh)
            }
        case .refreshIfStale:
            if let cached {
                vodInfo[video] = VideoInfo(cached: cached.value)
                if cached.isStale {
                    scheduleVodInfoRefresh(video, key: key)
                }
            } else {
                let fresh = try await refreshVodInfo(video, key: key)
                vodInfo[video] = VideoInfo(cached: fresh)
            }
        case .refreshNow:
            let fresh = try await refreshVodInfo(video, key: key)
            vodInfo[video] = VideoInfo(cached: fresh)
        }
    }

    private func refreshVodInfo(
        _ video: Video,
        key: CatalogMetadataCacheKey
    ) async throws -> CachedVideoInfoDTO {
        let fresh = try await metadataCacheManager.refreshPayload(
            for: key
        ) { [weak self] in
            guard let self else { throw CancellationError() }
            let dto = try await self.service().getVodInfo(of: String(video.id))
            return try JSONEncoder().encode(CachedVideoInfoDTO(VideoInfo(from: dto)))
        }
        let decoded = try decodeCachedValue(CachedVideoInfoDTO.self, from: fresh)
        vodInfo[video] = VideoInfo(cached: decoded)
        return decoded
    }

    private func scheduleVodInfoRefresh(_ video: Video, key: CatalogMetadataCacheKey) {
        runBackgroundActivity(
            id: "vod-detail-refresh:\(key.rawKey)",
            title: "Refreshing Movie Details",
            detail: video.name,
            source: "Details"
        ) { [weak self] in
            guard let self else { return }
            _ = try await self.refreshVodInfo(video, key: key)
        }
    }

    private func loadSeriesInfo(
        _ video: Video,
        policy: CatalogLoadPolicy
    ) async throws -> XtreamSeries {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }

        let key = try metadataKey(kind: .seriesInfo, resourceID: String(video.id))
        let cachedPayload = try await metadataCacheManager.cachedPayload(
            for: key,
            ttl: CatalogCacheTTL.details
        )
        let cached = try cachedPayload.map {
            CatalogCachedValue(
                value: try decodeCachedValue(XtreamSeries.self, from: $0.value),
                savedAt: $0.savedAt,
                isStale: $0.isStale
            )
        }

        switch policy {
        case .cachedOnly:
            guard let cached else { try cachedOnlyFailure(policy: policy) }
            seriesInfoBySeriesID[video.id] = cached.value
            return cached.value
        case .cachedThenRefresh:
            if let cached {
                seriesInfoBySeriesID[video.id] = cached.value
                scheduleSeriesInfoRefresh(video, key: key)
                return cached.value
            }
        case .refreshIfStale:
            if let cached {
                seriesInfoBySeriesID[video.id] = cached.value
                if cached.isStale {
                    scheduleSeriesInfoRefresh(video, key: key)
                }
                return cached.value
            }
        case .refreshNow:
            break
        }

        let fresh = try await refreshSeriesInfo(video, key: key)
        seriesInfoBySeriesID[video.id] = fresh
        return fresh
    }

    private func refreshSeriesInfo(
        _ video: Video,
        key: CatalogMetadataCacheKey
    ) async throws -> XtreamSeries {
        let fresh = try await metadataCacheManager.refreshPayload(
            for: key
        ) { [weak self] in
            guard let self else { throw CancellationError() }
            let value = try await self.service().getSeriesInfo(of: String(video.id))
            return try JSONEncoder().encode(value)
        }
        let decoded = try decodeCachedValue(XtreamSeries.self, from: fresh)
        seriesInfoBySeriesID[video.id] = decoded
        return decoded
    }

    private func scheduleSeriesInfoRefresh(_ video: Video, key: CatalogMetadataCacheKey) {
        runBackgroundActivity(
            id: "series-detail-refresh:\(key.rawKey)",
            title: "Refreshing Series Details",
            detail: video.name,
            source: "Details"
        ) { [weak self] in
            guard let self else { return }
            _ = try await self.refreshSeriesInfo(video, key: key)
        }
    }

    func getVodCategories(force: Bool = false) async throws {
        try await getVodCategories(policy: force ? .refreshNow : .refreshIfStale)
    }

    func getSeriesCategories(force: Bool = false) async throws {
        try await getSeriesCategories(policy: force ? .refreshNow : .refreshIfStale)
    }

    func getVodStreams(in category: Category, force: Bool = false) async throws {
        try await getVodStreams(in: category, policy: force ? .refreshNow : .refreshIfStale)
    }

    func getSeriesStreams(in category: Category, force: Bool = false) async throws {
        try await getSeriesStreams(in: category, policy: force ? .refreshNow : .refreshIfStale)
    }

    func getVodInfo(_ video: Video, force: Bool = false) async throws {
        try await getVodInfo(video, policy: force ? .refreshNow : .refreshIfStale)
    }

    func getSeriesInfo(_ video: Video, force: Bool = false) async throws -> XtreamSeries {
        try await getSeriesInfo(video, policy: force ? .refreshNow : .refreshIfStale)
    }

    func resolveURL(for video: Video) throws -> URL {
        let service = try self.service()
        return service.getPlayURL(for: video.id, type: video.contentType, containerExtension: video.containerExtension)
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

        let service = try self.service()
        return service.getPlayURL(
            for: episodeVideoID,
            type: XtreamContentType.series.rawValue,
            containerExtension: containerExtension
        )
    }

    func prepareDownloadMetadata(for video: Video) async throws -> DownloadPreparedMetadata {
        switch video.xtreamContentType {
        case .vod:
            try await getVodInfo(video, policy: .refreshIfStale)
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
            let seriesInfo = try await getSeriesInfo(video, policy: .refreshIfStale)
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
        let providerFingerprint = try currentProviderFingerprint()
        return await searchIndexStore.query(query, providerFingerprint: providerFingerprint)
    }

    func searchFacetValues(scope: SearchMediaScope) async throws -> SearchFacetValues {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        let providerFingerprint = try currentProviderFingerprint()
        return await searchIndexStore.facetValues(scope: scope, providerFingerprint: providerFingerprint)
    }

    func searchIndexProgress(scope: SearchMediaScope) async throws -> SearchIndexProgress {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        let providerFingerprint = try currentProviderFingerprint()
        return await searchIndexStore.progress(
            scope: scope,
            providerFingerprint: providerFingerprint,
            totalCategories: totalCategoryCount(for: scope)
        )
    }

    func ensureSearchCoverage(scope: SearchMediaScope) -> AsyncStream<SearchIndexProgress> {
        AsyncStream { continuation in
            Task { @MainActor in
                guard hasProviderConfiguration else {
                    continuation.yield(SearchIndexProgress(indexedCategories: 0, totalCategories: 0, scope: scope))
                    continuation.finish()
                    return
                }

                do {
                    let providerFingerprint = try currentProviderFingerprint()
                    let activityID = "search-coverage:\(providerFingerprint):\(scope.rawValue)"
                    if scope == .all || scope == .movies {
                        try await getVodCategories(force: false)
                    }
                    if scope == .all || scope == .series {
                        try await getSeriesCategories(force: false)
                    }

                    let targets = searchCoverageTargets(for: scope)
                    activityCenter.start(
                        id: activityID,
                        title: "Updating Search Index",
                        detail: "Preparing categories",
                        source: "Search",
                        progress: (0, max(targets.count, 1))
                    )
                    let progressStream = searchOrchestrator.ensureCoverage(
                        scope: scope,
                        providerFingerprint: providerFingerprint,
                        targets: targets,
                        progressProvider: { [searchIndexStore] in
                            await searchIndexStore.progress(
                                scope: scope,
                                providerFingerprint: providerFingerprint,
                                totalCategories: self.totalCategoryCount(for: scope)
                            )
                        },
                        fetch: { [weak self] target in
                            guard let self else { return }
                            do {
                                try await self.activityCenter.waitIfResumed()
                                switch target.contentType {
                                case .vod:
                                    try await self.getVodStreams(in: target.category, policy: .refreshIfStale)
                                case .series:
                                    try await self.getSeriesStreams(in: target.category, policy: .refreshIfStale)
                                case .live:
                                    break
                                }
                            } catch {
                                logger.debug("Search coverage fetch failed for category \(target.category.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            }
                        }
                    )

                    for await progress in progressStream {
                        self.activityCenter.update(
                            id: activityID,
                            detail: "Indexed \(progress.indexedCategories) of \(progress.totalCategories) categories",
                            progress: (progress.indexedCategories, max(progress.totalCategories, 1))
                        )
                        continuation.yield(progress)
                    }
                    activityCenter.finish(id: activityID, detail: "Search index is up to date")
                } catch is CancellationError {
                    if let providerFingerprint = try? currentProviderFingerprint() {
                        activityCenter.cancel(id: "search-coverage:\(providerFingerprint):\(scope.rawValue)")
                    }
                } catch {
                    if let providerFingerprint = try? currentProviderFingerprint() {
                        activityCenter.fail(id: "search-coverage:\(providerFingerprint):\(scope.rawValue)", error: error)
                    }
                    logger.debug("Search coverage stream failed: \(error.localizedDescription, privacy: .public)")
                }

                continuation.finish()
            }
        }
    }

    func clearSearchIndex() async {
        if let fingerprint = try? currentProviderFingerprint() {
            await searchIndexStore.clear(providerFingerprint: fingerprint)
            searchOrchestrator.cancelAll(providerFingerprint: fingerprint)
        } else {
            await searchIndexStore.clearAll()
            searchOrchestrator.cancelAll()
        }
    }

    private func totalCategoryCount(for scope: SearchMediaScope) -> Int {
        switch scope {
        case .all:
            vodCategories.count + seriesCategories.count
        case .movies:
            vodCategories.count
        case .series:
            seriesCategories.count
        }
    }

    private func searchCoverageTargets(for scope: SearchMediaScope) -> [SearchCoverageTarget] {
        var targets: [SearchCoverageTarget] = []
        if scope == .all || scope == .movies {
            targets.append(contentsOf: vodCategories.map { SearchCoverageTarget(contentType: .vod, category: $0) })
        }
        if scope == .all || scope == .series {
            targets.append(contentsOf: seriesCategories.map { SearchCoverageTarget(contentType: .series, category: $0) })
        }
        return targets
    }
}

extension Catalog {
    func getVodCategories(policy: CatalogLoadPolicy = .cachedThenRefresh) async throws {
        try await loadCategories(contentType: .vod, kind: .vodCategories, policy: policy)
    }

    func getSeriesCategories(policy: CatalogLoadPolicy = .cachedThenRefresh) async throws {
        try await loadCategories(contentType: .series, kind: .seriesCategories, policy: policy)
    }

    func getVodStreams(in category: Category, policy: CatalogLoadPolicy = .cachedThenRefresh) async throws {
        let categoryID = category.id
        try await loadStreams(in: category, contentType: .vod, policy: policy) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchVodStreamDTOs(inCategoryID: categoryID)
        }
    }

    func getSeriesStreams(in category: Category, policy: CatalogLoadPolicy = .cachedThenRefresh) async throws {
        let categoryID = category.id
        try await loadStreams(in: category, contentType: .series, policy: policy) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchSeriesStreamDTOs(inCategoryID: categoryID)
        }
    }

    func getVodInfo(_ video: Video, policy: CatalogLoadPolicy = .cachedThenRefresh) async throws {
        try await loadVodInfo(video, policy: policy)
    }

    func getSeriesInfo(_ video: Video, policy: CatalogLoadPolicy = .cachedThenRefresh) async throws -> XtreamSeries {
        try await loadSeriesInfo(video, policy: policy)
    }

    func clearProviderCaches() async throws {
        guard let fingerprint = try? currentProviderFingerprint() else {
            reset()
            return
        }

        await cacheManager.clearMemoryCache()
        await metadataCacheManager.clearMemoryCache()
        try await cacheManager.removeAll(for: fingerprint)
        try await metadataCacheManager.removeAll(for: fingerprint)
        await searchIndexStore.clear(providerFingerprint: fingerprint)
        searchOrchestrator.cancelAll(providerFingerprint: fingerprint)
        reset()
    }

    func clearMediaCache() {
        URLCache.shared.removeAllCachedResponses()
    }

    func rebuildSearchIndexFromCachedMetadata() async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        let fingerprint = try currentProviderFingerprint()
        let activityID = "search-index-rebuild:\(fingerprint)"
        await searchIndexStore.clear(providerFingerprint: fingerprint)

        let entries = try await cacheManager.entries(providerFingerprint: fingerprint)
        activityCenter.start(
            id: activityID,
            title: "Rebuilding Search Index",
            detail: "Scanning cached catalog data",
            source: "Search",
            progress: (0, max(entries.count, 1))
        )

        do {
            var processed = 0
            for entry in entries {
                try await activityCenter.waitIfResumed()
                let category = categories(for: entry.key.contentType).first { $0.id == entry.key.categoryID }
                    ?? Category(id: entry.key.categoryID, name: entry.key.categoryID)
                await storeSearchSnapshots(
                    from: entry.videos,
                    contentType: entry.key.contentType,
                    category: category,
                    providerFingerprint: fingerprint
                )
                processed += 1
                activityCenter.update(
                    id: activityID,
                    detail: "Processed \(processed) of \(entries.count) cached categories",
                    progress: (processed, max(entries.count, 1))
                )
            }
            activityCenter.finish(id: activityID, detail: "Search index rebuilt")
        } catch is CancellationError {
            activityCenter.cancel(id: activityID)
            throw CancellationError()
        } catch {
            activityCenter.fail(id: activityID, error: error)
            throw error
        }
    }

    func refreshCurrentProvider() async throws {
        try await getVodCategories(policy: .refreshNow)
        try await getSeriesCategories(policy: .refreshNow)
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
        switch contentType {
        case .vod:
            vodCatalog[category]
        case .series:
            seriesCatalog[category]
        case .live:
            liveCatalog[category]
        }
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
        try await getCategories(for: contentType, policy: force ? .refreshNow : .refreshIfStale)
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
        try await getStreams(in: category, contentType: contentType, policy: force ? .refreshNow : .refreshIfStale)
    }
}
