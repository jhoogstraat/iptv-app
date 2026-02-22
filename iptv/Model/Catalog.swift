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

@Observable
class Catalog {
    var vodCategories: [Category] = []
    var seriesCategories: [Category] = []
    
    var vodCatalog: [Category: [Video]] = [:]
    var seriesCatalog: [Category: [Video]] = [:]
    var liveCatalog: [Category: [Video]] = [:]
    
    var vodInfo: [Video: VideoInfo] = [:]
    
    private let providerStore: ProviderStore

    private var providerRevision: Int

    init(providerStore: ProviderStore, modelContainer: ModelContainer) {
        self.providerStore = providerStore
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
        guard force || vodCatalog[category] == nil else { return }
        let dto = try await self.service().getStreams(of: .vod, in: category.id)
        self.vodCatalog[category] = dto.map(Video.init)
    }

    func getSeriesStreams(in category: Category, force: Bool = false) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        guard force || seriesCatalog[category] == nil else { return }
        let service = try self.service()
        var dto = try await service.getSeries(in: category.id)
        if dto.isEmpty {
            let allSeries = try await service.getSeries()
            let filtered = allSeries.filter { $0.belongs(to: category.id) }
            dto = filtered.isEmpty ? allSeries : filtered
        }
        self.seriesCatalog[category] = dto.map(Video.init)
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
