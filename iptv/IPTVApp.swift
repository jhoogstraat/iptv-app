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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
                .environment(providerStore)
                .environment(catalog)
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
        
        // The video player window
        #if os(macOS)
        PlayerWindow(player: player)
        #endif
    }
    
    /// Load video metadata and initialize the model container and video player model.
    init() {
        do {
            let schema = Schema([])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
//            try Importer.importVideoMetadata(into: modelContainer.mainContext)
            let providerStore = ProviderStore()
            let watchActivityStore = DiskWatchActivityStore.shared
            self._providerStore = State(initialValue: providerStore)
            self._catalog = State(initialValue: Catalog(providerStore: providerStore, modelContainer: modelContainer))
            self._player = State(initialValue: Player(
                watchActivityStore: watchActivityStore,
                providerFingerprintProvider: {
                    guard let config = try? providerStore.configuration() else { return nil }
                    return ProviderCacheFingerprint.make(from: config)
                }
            ))
            self.modelContainer = modelContainer
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}

/// A global log of events for the app.
let logger = Logger()
