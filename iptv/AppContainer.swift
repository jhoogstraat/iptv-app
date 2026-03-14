//
//  AppContainer.swift
//  iptv
//
//  Created by Codex on 13.03.26.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppContainer {
    let modelContainer: ModelContainer
    let player: Player
    let providerStore: ProviderStore
    let catalog: Catalog
    let favoritesStore: FavoritesStore
    let watchActivityStore: any WatchActivityStoring
    let backgroundActivityCenter: BackgroundActivityCenter
    let backgroundCatalogueRefresher: BackgroundCatalogueRefresher
    let downloadCenter: DownloadCenter
    let connectionMonitor: InternetConnectionMonitor

    private let searchService: any SearchServing
    private let searchFavoritesStore: any SearchFavoriting
    private let searchProviderStore: any SearchProviderConfigurationProviding

    init(modelContainer: ModelContainer? = nil) throws {
        SharedImageURLCache.configureIfNeeded()

        let resolvedModelContainer: ModelContainer
        if let modelContainer {
            resolvedModelContainer = modelContainer
        } else {
            resolvedModelContainer = try AppPersistence.makeModelContainer()
        }

        let providerStore = ProviderStore()
        let favoritesStore = FavoritesStore(
            store: SwiftDataFavoritesStore(modelContainer: resolvedModelContainer)
        )
        let connectionMonitor = InternetConnectionMonitor.shared
        let backgroundActivityCenter = BackgroundActivityCenter(connectionMonitor: connectionMonitor)
        let backgroundCatalogueRefresher = BackgroundCatalogueRefresher()
        let watchActivityStore = SwiftDataWatchActivityStore(modelContainer: resolvedModelContainer)
        let imagePrefetcher = URLSessionImagePrefetcher()
        let player = Player(
            watchActivityStore: watchActivityStore,
            providerFingerprintProvider: {
                guard let config = try? providerStore.configuration() else { return nil }
                return ProviderCacheFingerprint.make(from: config)
            }
        )
        let catalog = Catalog(
            providerStore: providerStore,
            modelContainer: resolvedModelContainer,
            imagePrefetcher: imagePrefetcher,
            activityCenter: backgroundActivityCenter,
            backgroundCatalogueRefresher: backgroundCatalogueRefresher
        )

        self.modelContainer = resolvedModelContainer
        self.providerStore = providerStore
        self.catalog = catalog
        self.favoritesStore = favoritesStore
        self.watchActivityStore = watchActivityStore
        self.backgroundActivityCenter = backgroundActivityCenter
        self.backgroundCatalogueRefresher = backgroundCatalogueRefresher
        self.player = player
        self.connectionMonitor = connectionMonitor
        self.downloadCenter = DownloadCenter(
            providerStore: providerStore,
            catalog: catalog,
            backgroundActivityCenter: backgroundActivityCenter,
            store: DownloadStore(modelContainer: resolvedModelContainer),
            metadataStore: OfflineMetadataStore(modelContainer: resolvedModelContainer)
        )
        self.searchService = catalog
        self.searchFavoritesStore = favoritesStore
        self.searchProviderStore = providerStore

        configureUITestLaunchState()
    }

    func makeSearchViewModel() -> SearchScreenViewModel {
        SearchScreenViewModel(
            searchService: searchService,
            providerStore: searchProviderStore,
            favoritesStore: searchFavoritesStore
        )
    }

    func makeMoviesViewModel(contentType: XtreamContentType) -> MoviesScreenViewModel {
        MoviesScreenViewModel(contentType: contentType, catalog: catalog)
    }

    func makeForYouViewModel() -> ForYouViewModel {
        ForYouViewModel(
            dependencies: ForYouDependencies(
                providerConfigurationProvider: providerStore,
                categoryRepository: catalog,
                streamRepository: catalog,
                watchActivityStore: watchActivityStore,
                recommendationProvider: LocalRecommendationProvider()
            )
        )
    }

    private func configureUITestLaunchState() {
        let launchArgs = ProcessInfo.processInfo.arguments
        if launchArgs.contains("--uitest-open-player-series") {
            let episodes: [Video] = [
                Video(
                    id: 8001,
                    name: "Episode 1",
                    containerExtension: "mp4",
                    contentType: XtreamContentType.series.rawValue,
                    coverImageURL: nil,
                    tmdbId: nil,
                    rating: nil
                ),
                Video(
                    id: 8002,
                    name: "Episode 2",
                    containerExtension: "mp4",
                    contentType: XtreamContentType.series.rawValue,
                    coverImageURL: nil,
                    tmdbId: nil,
                    rating: nil
                )
            ]
            player.configureEpisodeSwitcher(episodes: episodes) { episode in
                guard let url = URL(string: "https://example.com/\(episode.id).mp4") else {
                    throw URLError(.badURL)
                }
                return .streaming(url)
            }
            if let first = episodes.first,
               let url = URL(string: "https://example.com/8001.mp4") {
                player.load(first, url, presentation: .fullWindow, autoplay: false)
            }
        } else if ProcessInfo.processInfo.arguments.contains("--uitest-open-player"),
                  let url = URL(string: "https://example.com/demo.mp4") {
            let video = Video(
                id: 9001,
                name: "UI Test Player Demo",
                containerExtension: "mp4",
                contentType: XtreamContentType.vod.rawValue,
                coverImageURL: nil,
                tmdbId: nil,
                rating: nil
            )
            player.load(video, url, presentation: .fullWindow, autoplay: false)
        }
    }
}
