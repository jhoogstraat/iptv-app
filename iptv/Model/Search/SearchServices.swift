//
//  SearchServices.swift
//  iptv
//
//  Created by Codex on 13.03.26.
//

import Foundation

@MainActor
protocol SearchServing: AnyObject {
    func search(_ query: SearchQuery) async throws -> [SearchResultItem]
    func searchFacetValues(scope: SearchMediaScope) async throws -> SearchFacetValues
    func ensureSearchCoverage(scope: SearchMediaScope) -> AsyncStream<SearchIndexProgress>
}

extension Catalog: SearchServing {}

@MainActor
protocol SearchProviderConfigurationProviding: AnyObject {
    var hasConfiguration: Bool { get }
    func requiredConfiguration() throws -> ProviderConfig
}

extension ProviderStore: SearchProviderConfigurationProviding {}

@MainActor
protocol SearchFavoriting: AnyObject {
    var revision: Int { get }
    func load(providerFingerprint: String) async -> [FavoriteRecord]
    func setFavorite(video: Video, providerFingerprint: String, isFavorite: Bool) async
}

extension FavoritesStore: SearchFavoriting {}
