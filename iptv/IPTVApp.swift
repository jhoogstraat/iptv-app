//
//  IPTVApp.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
//

import SwiftUI
import OSLog
import SQLiteData
import Dependencies
import Nuke
import Sharing

@MainActor
struct ApplicationRuntime {
    let providerManager: ProviderManager
    let player: Player
    let playbackDestinationCoordinator: PlaybackDestinationCoordinator
}

private struct ApplicationContentView: View {
    let bootstrap: RecoverableBootstrap<ApplicationRuntime>

    @ViewBuilder
    var body: some View {
        if let runtime = bootstrap.value {
            AppRootView()
                .withVideoPlayer()
                .environment(runtime.player)
                .environment(runtime.playbackDestinationCoordinator)
                .environment(runtime.providerManager)
        } else if let errorMessage = bootstrap.errorMessage {
            BootstrapFailureView(
                message: errorMessage,
                isRetrying: bootstrap.isLoading,
                retry: { bootstrap.retry() }
            )
        } else {
            ProgressView("Opening iptv…")
                .task { bootstrap.startIfNeeded() }
        }
    }
}

#if os(macOS)
private struct ApplicationSettingsContentView: View {
    let bootstrap: RecoverableBootstrap<ApplicationRuntime>

    @ViewBuilder
    var body: some View {
        if let runtime = bootstrap.value {
            SettingsScreen()
                .environment(runtime.providerManager)
        } else if let errorMessage = bootstrap.errorMessage {
            BootstrapFailureView(
                message: errorMessage,
                isRetrying: bootstrap.isLoading,
                retry: { bootstrap.retry() }
            )
        } else {
            ProgressView("Opening iptv…")
                .task { bootstrap.startIfNeeded() }
        }
    }
}
#endif

@main
struct IPTVApp: App {
    @State private var bootstrap: RecoverableBootstrap<ApplicationRuntime>

    var body: some Scene {
        WindowGroup {
            ApplicationContentView(bootstrap: bootstrap)
#if os(macOS)
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
#endif
                .preferredColorScheme(.dark)
        }
        #if !os(tvOS)
        .windowResizability(.contentSize)
        #endif

        #if os(macOS)
        Settings {
            ApplicationSettingsContentView(bootstrap: bootstrap)
        }

        PlayerWindow(bootstrap: bootstrap)
        #endif
    }

    
    /// Loads persistence and session state behind a retryable boundary.
    init() {
        let bootstrap = RecoverableBootstrap<ApplicationRuntime> {
            let credentialStore = KeychainProviderCredentialStore()
            let database = try appDatabase(credentialStore: credentialStore)
            prepareDependencies {
                $0.defaultDatabase = database
                $0.defaultAppStorage = UserDefaults.standard
            }

            let providerManager = ProviderManager(
                database: database,
                credentialStore: credentialStore
            )
            try providerManager.loadActive()

            let player = Player(database: database, credentialStore: credentialStore)
            let playbackDestinationCoordinator = PlaybackDestinationCoordinator()
            playbackDestinationCoordinator.bind(player: player)
            let runtime = ApplicationRuntime(
                providerManager: providerManager,
                player: player,
                playbackDestinationCoordinator: playbackDestinationCoordinator
            )
            ExternalDisplayRuntimeBridge.shared.install(runtime)
            return runtime
        }

        bootstrap.startIfNeeded()
        self._bootstrap = State(initialValue: bootstrap)

        ImagePipeline.Configuration.isSignpostLoggingEnabled = true
    }
}


/// A global log of events for the app.
private let logger = Logger()
