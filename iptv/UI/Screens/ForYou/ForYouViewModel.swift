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
    private let watchActivityStore: WatchActivityStore
    private let recommendationProvider: any RecommendationProviding

    private let vodCategoryLimit: Int
    private let seriesCategoryLimit: Int

    var phase: Phase = .idle
    var hero: ForYouItem?
    var sections: [ForYouSection] = []
    var isRefreshing = false
    var lastRefresh: Date?

    private var lastLoadedProviderFingerprint: String?
    private var activeLoadID = UUID()

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
        let loadID = UUID()

        guard providerConfigurationProvider.hasProviderConfiguration else {
            phase = .idle
            hero = nil
            sections = []
            isRefreshing = false
            lastLoadedProviderFingerprint = nil
            return
        }

        do {
            let providerFingerprint = try currentProviderFingerprint()
            let hasExistingContent = hero != nil || !sections.isEmpty
            let isLoadedPhase: Bool
            if case .loaded = phase {
                isLoadedPhase = true
            } else {
                isLoadedPhase = false
            }

            let shouldSkipWarmRead = policy == .readThrough
                && lastLoadedProviderFingerprint == providerFingerprint
                && isLoadedPhase
                && hasExistingContent

            guard !shouldSkipWarmRead else { return }

            let shouldShowBlockingLoading = !hasExistingContent || lastLoadedProviderFingerprint != providerFingerprint
            activeLoadID = loadID
            isRefreshing = true

            if shouldShowBlockingLoading {
                phase = .loading
            }

            defer {
                if activeLoadID == loadID {
                    isRefreshing = false
                }
            }

            async let vodOutcome = loadCategories(
                policy: policy,
                contentType: .vod,
                limit: vodCategoryLimit
            )
            async let seriesOutcome = loadCategories(
                policy: policy,
                contentType: .series,
                limit: seriesCategoryLimit
            )
            async let watchRecords = watchActivityStore.load(providerFingerprint: providerFingerprint)

            let (resolvedVodOutcome, resolvedSeriesOutcome, records) = await (vodOutcome, seriesOutcome, watchRecords)

            if resolvedVodOutcome.error is CancellationError || resolvedSeriesOutcome.error is CancellationError {
                throw CancellationError()
            }

            if resolvedVodOutcome.categories.isEmpty, resolvedSeriesOutcome.categories.isEmpty {
                throw resolvedVodOutcome.error ?? resolvedSeriesOutcome.error ?? CatalogError.missingProviderConfiguration
            }

            let context = RecommendationContext(
                providerFingerprint: providerFingerprint,
                watchRecords: records,
                vodCategories: resolvedVodOutcome.categories,
                seriesCategories: resolvedSeriesOutcome.categories,
                vodCatalog: resolvedVodOutcome.categories.reduce(into: [:]) { partialResult, category in
                    partialResult[category] = streamRepository.videos(in: category, contentType: .vod)
                },
                seriesCatalog: resolvedSeriesOutcome.categories.reduce(into: [:]) { partialResult, category in
                    partialResult[category] = streamRepository.videos(in: category, contentType: .series)
                }
            )

            let output = try await recommendationProvider.build(context: context)
            guard activeLoadID == loadID else { return }

            hero = output.hero
            sections = output.sections
            lastRefresh = Date()
            lastLoadedProviderFingerprint = providerFingerprint
            phase = .loaded
        } catch is CancellationError {
            guard activeLoadID == loadID else { return }
            logger.debug("ForYou load cancelled")
        } catch {
            guard activeLoadID == loadID else { return }
            logger.error("ForYou load failed: \(error.localizedDescription, privacy: .public)")
            if hero == nil && sections.isEmpty {
                phase = .failed(error)
            }
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
