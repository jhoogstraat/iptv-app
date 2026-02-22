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

    private var providerRevision: Int

    init(
        providerStore: ProviderStore,
        modelContainer: ModelContainer,
        cacheManager: CatalogCacheManager = CatalogCacheManager(),
        imagePrefetcher: ImagePrefetching = NoopImagePrefetcher()
    ) {
        self.providerStore = providerStore
        self.cacheManager = cacheManager
        self.imagePrefetcher = imagePrefetcher
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
}
