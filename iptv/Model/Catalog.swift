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

    var errorDescription: String? {
        switch self {
        case .missingProviderConfiguration:
            return "Configure your provider in Settings before loading content."
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

    private let providerStore: ProviderStore
    private let cacheManager: CatalogCacheManager
    private let imagePrefetcher: ImagePrefetching
    private let searchIndexStore: SearchIndexStore
    private let searchOrchestrator: SearchOrchestrator

    private var providerRevision: Int

    init(
        providerStore: ProviderStore,
        modelContainer: ModelContainer,
        cacheManager: CatalogCacheManager = CatalogCacheManager(),
        imagePrefetcher: ImagePrefetching = NoopImagePrefetcher(),
        searchIndexStore: SearchIndexStore = SearchIndexStore(),
        searchOrchestrator: SearchOrchestrator? = nil
    ) {
        self.providerStore = providerStore
        self.cacheManager = cacheManager
        self.imagePrefetcher = imagePrefetcher
        self.searchIndexStore = searchIndexStore
        self.searchOrchestrator = searchOrchestrator ?? SearchOrchestrator()
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
        Task(priority: .utility) {
            await cacheManager.clearMemoryCache()
            await searchIndexStore.clearAll()
            await searchOrchestrator.cancelAll()
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

    func getVodCategories(force: Bool = false) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        guard force || vodCategories.isEmpty else { return }
        let dto = try await self.service().getCategories(of: .vod)
        self.vodCategories = dto.map(Category.init)
    }

    func getSeriesCategories(force: Bool = false) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        guard force || seriesCategories.isEmpty else { return }
        let dto = try await self.service().getCategories(of: .series)
        self.seriesCategories = dto.map(Category.init)
    }

    func getVodStreams(in category: Category, force: Bool = false) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }

        let service = try self.service()
        let key = try cacheKey(for: category, contentType: .vod)
        let categoryID = category.id

        let cachedVideos = try await cacheManager.loadStreamList(for: key, force: force) {
            let streams = try await service.getStreams(of: .vod, in: categoryID)
            return streams.map(CachedVideoDTO.init)
        }

        self.vodCatalog[category] = cachedVideos.map(Video.init)
        let snapshots = cachedVideos.map(SearchVideoSnapshot.init(cachedVideo:))
        await searchIndexStore.upsert(
            videos: snapshots,
            contentType: .vod,
            categoryID: category.id,
            categoryName: category.name,
            providerFingerprint: key.providerFingerprint
        )
    }

    func getSeriesStreams(in category: Category, force: Bool = false) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }

        let service = try self.service()
        let key = try cacheKey(for: category, contentType: .series)
        let categoryID = category.id

        let cachedVideos = try await cacheManager.loadStreamList(for: key, force: force) {
            var series = try await service.getSeries(in: categoryID)
            if series.isEmpty {
                let allSeries = try await service.getSeries()
                let filtered = allSeries.filter { $0.belongs(to: categoryID) }
                series = filtered.isEmpty ? allSeries : filtered
            }
            return series.map(CachedVideoDTO.init)
        }

        self.seriesCatalog[category] = cachedVideos.map(Video.init)
        let snapshots = cachedVideos.map(SearchVideoSnapshot.init(cachedVideo:))
        await searchIndexStore.upsert(
            videos: snapshots,
            contentType: .series,
            categoryID: category.id,
            categoryName: category.name,
            providerFingerprint: key.providerFingerprint
        )
    }

    func getVodInfo(_ video: Video, force: Bool = false) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        guard force || vodInfo[video] == nil else { return }
        let dto = try await self.service().getVodInfo(of: String(video.id))
        self.vodInfo[video] = VideoInfo(from: dto)
    }

    func resolveURL(for video: Video) throws -> URL {
        let service = try self.service()
        return service.getPlayURL(for: video.id, type: video.contentType, containerExtension: video.containerExtension)
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
                    if scope == .all || scope == .movies {
                        try await getVodCategories(force: false)
                    }
                    if scope == .all || scope == .series {
                        try await getSeriesCategories(force: false)
                    }

                    let targets = searchCoverageTargets(for: scope)
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
                                switch target.contentType {
                                case .vod:
                                    try await self.getVodStreams(in: target.category)
                                case .series:
                                    try await self.getSeriesStreams(in: target.category)
                                case .live:
                                    break
                                }
                            } catch {
                                logger.debug("Search coverage fetch failed for category \(target.category.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            }
                        }
                    )

                    for await progress in progressStream {
                        continuation.yield(progress)
                    }
                } catch {
                    logger.debug("Search coverage stream failed: \(error.localizedDescription, privacy: .public)")
                }

                continuation.finish()
            }
        }
    }

    func clearSearchIndex() async {
        if let fingerprint = try? currentProviderFingerprint() {
            await searchIndexStore.clear(providerFingerprint: fingerprint)
            await searchOrchestrator.cancelAll(providerFingerprint: fingerprint)
        } else {
            await searchIndexStore.clearAll()
            await searchOrchestrator.cancelAll()
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
