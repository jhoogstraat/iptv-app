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
    private struct CategoryLoadOutcome {
        let categories: [Category]
        let error: Error?
    }

    enum Phase {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    private let providerConfigurationProvider: any ProviderConfigurationProviding
    private let categoryRepository: any CategoryRepository
    private let streamRepository: any StreamRepository
    private let watchActivityStore: any WatchActivityStoring
    private let recommendationProvider: any RecommendationProviding

    private let vodCategoryLimit: Int
    private let seriesCategoryLimit: Int

    var phase: Phase = .idle
    var hero: ForYouItem?
    var sections: [ForYouSection] = []
    var lastRefresh: Date?

    init(
        dependencies: ForYouDependencies,
        vodCategoryLimit: Int = 8,
        seriesCategoryLimit: Int = 6
    ) {
        self.providerConfigurationProvider = dependencies.providerConfigurationProvider
        self.categoryRepository = dependencies.categoryRepository
        self.streamRepository = dependencies.streamRepository
        self.watchActivityStore = dependencies.watchActivityStore
        self.recommendationProvider = dependencies.recommendationProvider
        self.vodCategoryLimit = vodCategoryLimit
        self.seriesCategoryLimit = seriesCategoryLimit
    }

    func load(policy: CatalogLoadPolicy = .readThrough) async {
        guard providerConfigurationProvider.hasProviderConfiguration else {
            phase = .idle
            hero = nil
            sections = []
            return
        }

        do {
            phase = .loading

            let vodOutcome = await loadCategories(
                policy: policy,
                contentType: .vod,
                limit: vodCategoryLimit
            )
            let seriesOutcome = await loadCategories(
                policy: policy,
                contentType: .series,
                limit: seriesCategoryLimit
            )

            if vodOutcome.error is CancellationError || seriesOutcome.error is CancellationError {
                throw CancellationError()
            }

            if vodOutcome.categories.isEmpty, seriesOutcome.categories.isEmpty {
                throw vodOutcome.error ?? seriesOutcome.error ?? CatalogError.missingProviderConfiguration
            }

            let providerFingerprint = try currentProviderFingerprint()
            let records = await watchActivityStore.loadAll()
                .filter { $0.providerFingerprint == providerFingerprint }

            let context = RecommendationContext(
                providerFingerprint: providerFingerprint,
                watchRecords: records,
                vodCategories: vodOutcome.categories,
                seriesCategories: seriesOutcome.categories,
                vodCatalog: vodOutcome.categories.reduce(into: [:]) { partialResult, category in
                    partialResult[category] = streamRepository.videos(in: category, contentType: .vod)
                },
                seriesCatalog: seriesOutcome.categories.reduce(into: [:]) { partialResult, category in
                    partialResult[category] = streamRepository.videos(in: category, contentType: .series)
                }
            )

            let output = try await recommendationProvider.build(context: context)

            hero = output.hero
            sections = output.sections
            lastRefresh = Date()
            phase = .loaded
        } catch is CancellationError {
            logger.debug("ForYou load cancelled")
        } catch {
            logger.error("ForYou load failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error)
        }
    }

    func refresh() async {
        await load(policy: .forceRefresh)
    }

    private func currentProviderFingerprint() throws -> String {
        let config = try providerConfigurationProvider.requiredConfiguration()
        return ProviderCacheFingerprint.make(from: config)
    }

    private func loadCategories(
        policy: CatalogLoadPolicy,
        contentType: XtreamContentType,
        limit: Int
    ) async -> CategoryLoadOutcome {
        var loadError: Error?

        do {
            try await loadCategoriesWithRetry(policy: policy, contentType: contentType)
        } catch is CancellationError {
            return CategoryLoadOutcome(categories: [], error: CancellationError())
        } catch {
            loadError = error
            logger.debug("ForYou \(contentType.rawValue, privacy: .public) categories failed: \(error.localizedDescription, privacy: .public)")
        }

        let categories = Array(categoryRepository.categories(for: contentType).prefix(limit))
        return CategoryLoadOutcome(categories: categories, error: categories.isEmpty ? loadError : nil)
    }

    private func loadCategoriesWithRetry(
        policy: CatalogLoadPolicy,
        contentType: XtreamContentType,
        retries: Int = 1
    ) async throws {
        var attemptsRemaining = retries

        while true {
            do {
                try await categoryRepository.loadCategories(for: contentType, policy: policy)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attemptsRemaining > 0, shouldRetryCategoryLoad(for: error) else {
                    throw error
                }

                attemptsRemaining -= 1
                try await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    private func shouldRetryCategoryLoad(for error: Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed,
                 .secureConnectionFailed:
                return true
            default:
                return false
            }
        }

        if case NetworkError.invalidResponse = error {
            return true
        }

        if case NetworkError.httpError(let statusCode) = error {
            return statusCode == 429 || (500...599).contains(statusCode)
        }

        return false
    }
}
