//
//  ForYouViewModel.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class ForYouViewModel {
    enum Phase {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    private let catalog: Catalog
    private let providerStore: ProviderStore
    private let watchActivityStore: any WatchActivityStoring
    private let recommendationProvider: any RecommendationProviding

    private let vodCategoryLimit: Int
    private let seriesCategoryLimit: Int

    var phase: Phase = .idle
    var hero: ForYouItem?
    var sections: [ForYouSection] = []
    var lastRefresh: Date?

    init(
        catalog: Catalog,
        providerStore: ProviderStore,
        watchActivityStore: any WatchActivityStoring = DiskWatchActivityStore.shared,
        recommendationProvider: any RecommendationProviding = LocalRecommendationProvider(),
        vodCategoryLimit: Int = 8,
        seriesCategoryLimit: Int = 6
    ) {
        self.catalog = catalog
        self.providerStore = providerStore
        self.watchActivityStore = watchActivityStore
        self.recommendationProvider = recommendationProvider
        self.vodCategoryLimit = vodCategoryLimit
        self.seriesCategoryLimit = seriesCategoryLimit
    }

    func load(force: Bool = false) async {
        guard providerStore.hasConfiguration else {
            phase = .idle
            hero = nil
            sections = []
            return
        }

        do {
            phase = .loading

            try await catalog.getVodCategories(force: force)
            try await catalog.getSeriesCategories(force: force)

            let selectedVodCategories = Array(catalog.vodCategories.prefix(vodCategoryLimit))
            let selectedSeriesCategories = Array(catalog.seriesCategories.prefix(seriesCategoryLimit))

            for category in selectedVodCategories {
                do {
                    try await catalog.getVodStreams(in: category, force: force)
                } catch {
                    logger.debug("ForYou VOD prefetch failed for category \(category.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            for category in selectedSeriesCategories {
                do {
                    try await catalog.getSeriesStreams(in: category, force: force)
                } catch {
                    logger.debug("ForYou series prefetch failed for category \(category.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            let providerFingerprint = try currentProviderFingerprint()
            let records = await watchActivityStore.loadAll()
                .filter { $0.providerFingerprint == providerFingerprint }

            let context = RecommendationContext(
                providerFingerprint: providerFingerprint,
                watchRecords: records,
                vodCategories: selectedVodCategories,
                seriesCategories: selectedSeriesCategories,
                vodCatalog: selectedVodCategories.reduce(into: [:]) { partialResult, category in
                    partialResult[category] = catalog.vodCatalog[category] ?? []
                },
                seriesCatalog: selectedSeriesCategories.reduce(into: [:]) { partialResult, category in
                    partialResult[category] = catalog.seriesCatalog[category] ?? []
                }
            )

            let output = try await recommendationProvider.build(context: context)

            hero = output.hero
            sections = output.sections
            lastRefresh = Date()
            phase = .loaded
        } catch {
            logger.error("ForYou load failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error)
        }
    }

    func refresh() async {
        await load(force: true)
    }

    private func currentProviderFingerprint() throws -> String {
        let config = try providerStore.requiredConfiguration()
        return ProviderCacheFingerprint.make(from: config)
    }
}
