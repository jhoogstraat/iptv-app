//
//  ForYouDependencies.swift
//  iptv
//
//  Created by Codex on 13.03.26.
//

import Foundation

@MainActor
struct ForYouDependencies {
    let providerConfigurationProvider: any ProviderConfigurationProviding
    let categoryRepository: any CategoryRepository
    let streamRepository: any StreamRepository
    let watchActivityStore: WatchActivityStore
    let recommendationProvider: any RecommendationProviding

    init(
        providerConfigurationProvider: any ProviderConfigurationProviding,
        categoryRepository: any CategoryRepository,
        streamRepository: any StreamRepository,
        watchActivityStore: WatchActivityStore,
        recommendationProvider: any RecommendationProviding = LocalRecommendationProvider()
    ) {
        self.providerConfigurationProvider = providerConfigurationProvider
        self.categoryRepository = categoryRepository
        self.streamRepository = streamRepository
        self.watchActivityStore = watchActivityStore
        self.recommendationProvider = recommendationProvider
    }
}
