//
//  IPTVApp.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
//

import SwiftUI
import SwiftData
import OSLog

@main
struct IPTVApp: App {
    /// An object that manages the model storage configuration.
    private let modelContainer: ModelContainer

    /// An object that controls the video playback behavior.
    @State private var player: Player
    @State private var providerStore: ProviderStore
    @State private var catalog: Catalog
    @State private var favoritesStore: FavoritesStore
    @State private var backgroundActivityCenter: BackgroundActivityCenter
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
                .environment(providerStore)
                .environment(catalog)
                .environment(favoritesStore)
                .environment(backgroundActivityCenter)
                .modelContainer(modelContainer)
                #if os(macOS)
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                #endif
                // Set minimum window size
                #if os(macOS) || os(visionOS)
                .frame(minWidth: 600, maxWidth: .infinity, minHeight: 960, maxHeight: .infinity)
                #endif
                // Use a dark color scheme on supported platforms.
                #if os(iOS) || os(macOS)
                .preferredColorScheme(.dark)
                #endif
        }
        #if !os(tvOS)
        .windowResizability(.contentSize)
        #endif

        #if os(macOS)
        Settings {
            SettingsScreen()
                .environment(providerStore)
        }
        #endif
        
        // The video player window
        #if os(macOS)
        PlayerWindow(
            player: player,
            providerStore: providerStore,
            favoritesStore: favoritesStore
        )
        #endif
    }
    
    /// Load video metadata and initialize the model container and video player model.
    init() {
        do {
            SharedImageURLCache.configureIfNeeded()

            let schema = Schema([])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
//            try Importer.importVideoMetadata(into: modelContainer.mainContext)
            let providerStore = ProviderStore()
            let favoritesStore = FavoritesStore()
            let backgroundActivityCenter = BackgroundActivityCenter()
            let watchActivityStore = DiskWatchActivityStore.shared
            let imagePrefetcher = URLSessionImagePrefetcher()
            let player = Player(
                watchActivityStore: watchActivityStore,
                providerFingerprintProvider: {
                    guard let config = try? providerStore.configuration() else { return nil }
                    return ProviderCacheFingerprint.make(from: config)
                }
            )
            self._providerStore = State(initialValue: providerStore)
            self._favoritesStore = State(initialValue: favoritesStore)
            self._backgroundActivityCenter = State(initialValue: backgroundActivityCenter)
            self._catalog = State(initialValue: Catalog(
                providerStore: providerStore,
                modelContainer: modelContainer,
                imagePrefetcher: imagePrefetcher,
                activityCenter: backgroundActivityCenter
            ))

            let launchArgs = ProcessInfo.processInfo.arguments
            if launchArgs.contains("--uitest-open-player-series") {
                let episodes: [Video] = [
                    Video(id: 8001, name: "Episode 1", containerExtension: "mp4", contentType: XtreamContentType.series.rawValue, coverImageURL: nil, tmdbId: nil, rating: nil),
                    Video(id: 8002, name: "Episode 2", containerExtension: "mp4", contentType: XtreamContentType.series.rawValue, coverImageURL: nil, tmdbId: nil, rating: nil)
                ]
                player.configureEpisodeSwitcher(episodes: episodes) { episode in
                    guard let url = URL(string: "https://example.com/\(episode.id).mp4") else {
                        throw URLError(.badURL)
                    }
                    return url
                }
                if let first = episodes.first,
                   let url = URL(string: "https://example.com/8001.mp4") {
                    player.load(first, url, presentation: .fullWindow, autoplay: false)
                }
            } else if launchArgs.contains("--uitest-open-player"),
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

            self._player = State(initialValue: player)
            self.modelContainer = modelContainer
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}

/// A global log of events for the app.
let logger = Logger()
