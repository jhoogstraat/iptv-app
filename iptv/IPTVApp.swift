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

    @State private var appContainer: AppContainer
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appContainer)
                .environment(appContainer.player)
                .environment(appContainer.providerStore)
                .environment(appContainer.catalog)
                .environment(appContainer.favoritesStore)
                .environment(appContainer.backgroundActivityCenter)
                .environment(appContainer.downloadCenter)
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
                .environment(appContainer.providerStore)
        }
        #endif
        
        // The video player window
        #if os(macOS)
        PlayerWindow(
            player: appContainer.player,
            catalog: appContainer.catalog,
            providerStore: appContainer.providerStore,
            favoritesStore: appContainer.favoritesStore
        )
        #endif
    }
    
    /// Load video metadata and initialize the model container and video player model.
    init() {
        do {
            let appContainer = try AppContainer()
            self._appContainer = State(initialValue: appContainer)
            self.modelContainer = appContainer.modelContainer
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}

/// A global log of events for the app.
let logger = Logger()
