//
//  SearchScreenViewModel.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class SearchScreenViewModel {
    enum Phase {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    private let catalog: Catalog
    private let providerStore: ProviderStore
    private let favoritesStore: FavoritesStore

    var phase: Phase = .idle
    var queryText = ""
    var scope: SearchMediaScope = .all
    var sort: SearchSort = .relevance
    var filters: SearchFilters = .default
    var results: [SearchResultItem] = []
    var indexProgress = SearchIndexProgress(indexedCategories: 0, totalCategories: 0, scope: .all)
    var availableGenres: [String] = []
    var availableLanguages: [String] = []
    var favoriteIDs: Set<String> = []

    private var searchTask: Task<Void, Never>?
    private var coverageTask: Task<Void, Never>?

    init(catalog: Catalog, providerStore: ProviderStore, favoritesStore: FavoritesStore) {
        self.catalog = catalog
        self.providerStore = providerStore
        self.favoritesStore = favoritesStore
    }

    func start() {
        guard providerStore.hasConfiguration else {
            phase = .idle
            results = []
            indexProgress = SearchIndexProgress(indexedCategories: 0, totalCategories: 0, scope: scope)
            return
        }

        coverageTask?.cancel()
        coverageTask = Task { [weak self] in
            guard let self else { return }
            await self.consumeCoverageStream()
        }

        Task { [weak self] in
            guard let self else { return }
            await self.refreshFacets()
            await self.refreshFavorites()
            await self.runSearch()
        }
    }

    func setScope(_ newScope: SearchMediaScope) {
        guard scope != newScope else { return }
        scope = newScope
        filters.genres.removeAll()
        filters.languages.removeAll()
        indexProgress = SearchIndexProgress(indexedCategories: 0, totalCategories: 0, scope: newScope)
        start()
    }

    func scheduleSearch(debounced: Bool = true) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            if debounced {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            await self.runSearch()
        }
    }

    func clearFilterSelections() {
        filters = .default
        scheduleSearch(debounced: false)
    }

    func isFavorite(_ item: SearchResultItem) -> Bool {
        let key = FavoriteRecord.makeKey(
            providerFingerprint: (try? currentProviderFingerprint()) ?? "",
            contentType: item.video.contentType,
            videoID: item.video.id
        )
        return favoriteIDs.contains(key)
    }

    private func runSearch() async {
        guard providerStore.hasConfiguration else {
            phase = .idle
            results = []
            return
        }

        let hasText = !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasFilters = filters.minRating != nil
            || filters.maxRating != nil
            || !filters.genres.isEmpty
            || !filters.languages.isEmpty
            || filters.addedWindow != .any

        if !hasText && !hasFilters {
            phase = .idle
            results = []
            return
        }

        do {
            phase = .loading
            let query = SearchQuery(
                text: queryText,
                scope: scope,
                filters: filters,
                sort: sort
            )
            results = try await catalog.search(query)
            await refreshFavorites()
            phase = .loaded
        } catch {
            phase = .failed(error)
        }
    }

    private func consumeCoverageStream() async {
        let stream = catalog.ensureSearchCoverage(scope: scope)
        for await progress in stream {
            if Task.isCancelled { return }
            indexProgress = progress
        }
        await refreshFacets()
    }

    private func refreshFacets() async {
        guard providerStore.hasConfiguration else {
            availableGenres = []
            availableLanguages = []
            return
        }
        do {
            let facets = try await catalog.searchFacetValues(scope: scope)
            availableGenres = facets.genres
            availableLanguages = facets.languages
        } catch {
            availableGenres = []
            availableLanguages = []
        }
    }

    private func refreshFavorites() async {
        guard let fingerprint = try? currentProviderFingerprint() else {
            favoriteIDs = []
            return
        }
        let favorites = await favoritesStore.load(providerFingerprint: fingerprint)
        favoriteIDs = Set(favorites.map(\.id))
    }

    private func currentProviderFingerprint() throws -> String {
        let config = try providerStore.requiredConfiguration()
        return ProviderCacheFingerprint.make(from: config)
    }
}
