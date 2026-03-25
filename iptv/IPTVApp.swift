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

@main
struct IPTVApp: App {
    private let providerManager: ProviderManager
    private let mustOnboard: Bool
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(providerManager)
#if os(macOS)
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif

#if os(macOS) || os(visionOS)
                .frame(minWidth: 600, maxWidth: .infinity, minHeight: 960, maxHeight: .infinity)
#endif
                .preferredColorScheme(.dark)
        }
        #if !os(tvOS)
        .windowResizability(.contentSize)
        #endif

        #if os(macOS)
        Settings {
            SettingsScreen()
                .environment(providerManager)
        }
        #endif
        
        // The video player window
        #if os(macOS)
        // TODO: Implement player
//        PlayerWindow()
        #endif
    }
    
    /// Load video metadata and initialize the model container and video player model.
    init() {
        prepareDependencies {
            $0.defaultDatabase = try! appDatabase()
            $0.defaultAppStorage = UserDefaults.standard
        }
        
        let providerManager = ProviderManager()
       
        // FIXME: Handle error gracefully
        try! providerManager.loadActive()
        
        ImagePipeline.Configuration.isSignpostLoggingEnabled = true

        self.providerManager = providerManager
        self.mustOnboard = !providerManager.hasActiveProvider
    }
}


/// A global log of events for the app.
private let logger = Logger()
