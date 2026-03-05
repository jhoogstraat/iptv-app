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

    private var sessionID = UUID()
    private var searchTask: Task<Void, Never>?
    private var coverageTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?

    init(catalog: Catalog, providerStore: ProviderStore, favoritesStore: FavoritesStore) {
        self.catalog = catalog
        self.providerStore = providerStore
        self.favoritesStore = favoritesStore
    }

    func start() {
        cancelTasks()
        sessionID = UUID()

        guard providerStore.hasConfiguration else {
            phase = .idle
            results = []
            indexProgress = SearchIndexProgress(indexedCategories: 0, totalCategories: 0, scope: scope)
            return
        }

        let activeSession = sessionID
        let activeScope = scope

        coverageTask = Task { [weak self] in
            guard let self else { return }
            await self.consumeCoverageStream(scope: activeScope, sessionID: activeSession)
        }

        startupTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshFacets(scope: activeScope, sessionID: activeSession)
            await self.refreshFavorites(sessionID: activeSession)
            await self.runSearch(scope: activeScope, sessionID: activeSession)
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
        let activeSession = sessionID
        let activeScope = scope
        searchTask = Task { [weak self] in
            guard let self else { return }
            if debounced {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            await self.runSearch(scope: activeScope, sessionID: activeSession)
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

    private func runSearch(scope requestedScope: SearchMediaScope, sessionID: UUID) async {
        guard isCurrent(sessionID, scope: requestedScope) else { return }
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
                scope: requestedScope,
                filters: filters,
                sort: sort
            )
            let searchResults = try await catalog.search(query)
            guard isCurrent(sessionID, scope: requestedScope), !Task.isCancelled else { return }
            results = searchResults
            await refreshFavorites(sessionID: sessionID)
            guard isCurrent(sessionID, scope: requestedScope), !Task.isCancelled else { return }
            phase = .loaded
        } catch {
            guard isCurrent(sessionID, scope: requestedScope), !Task.isCancelled else { return }
            phase = .failed(error)
        }
    }

    private func consumeCoverageStream(scope requestedScope: SearchMediaScope, sessionID: UUID) async {
        let stream = catalog.ensureSearchCoverage(scope: requestedScope)
        for await progress in stream {
            if Task.isCancelled { return }
            guard isCurrent(sessionID, scope: requestedScope) else { return }
            indexProgress = progress
        }
        await refreshFacets(scope: requestedScope, sessionID: sessionID)
    }

    private func refreshFacets(scope requestedScope: SearchMediaScope, sessionID: UUID) async {
        guard isCurrent(sessionID, scope: requestedScope) else { return }
        guard providerStore.hasConfiguration else {
            availableGenres = []
            availableLanguages = []
            return
        }
        do {
            let facets = try await catalog.searchFacetValues(scope: requestedScope)
            guard isCurrent(sessionID, scope: requestedScope), !Task.isCancelled else { return }
            availableGenres = facets.genres
            availableLanguages = facets.languages
        } catch {
            guard isCurrent(sessionID, scope: requestedScope), !Task.isCancelled else { return }
            availableGenres = []
            availableLanguages = []
        }
    }

    private func refreshFavorites(sessionID: UUID) async {
        guard isCurrent(sessionID) else { return }
        guard let fingerprint = try? currentProviderFingerprint() else {
            favoriteIDs = []
            return
        }
        let favorites = await favoritesStore.load(providerFingerprint: fingerprint)
        guard isCurrent(sessionID), !Task.isCancelled else { return }
        favoriteIDs = Set(favorites.map(\.id))
    }

    private func currentProviderFingerprint() throws -> String {
        let config = try providerStore.requiredConfiguration()
        return ProviderCacheFingerprint.make(from: config)
    }

    private func cancelTasks() {
        searchTask?.cancel()
        coverageTask?.cancel()
        startupTask?.cancel()
    }

    private func isCurrent(_ sessionID: UUID, scope expectedScope: SearchMediaScope? = nil) -> Bool {
        guard self.sessionID == sessionID else { return false }
        if let expectedScope {
            return scope == expectedScope
        }
        return true
    }
}
