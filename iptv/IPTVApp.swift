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
    private let sessionManager: SessionManager
    
    var body: some Scene {
        WindowGroup {
            if let session = sessionManager.session {
                ContentView()
                    .environment(sessionManager)
                    .environment(session)
#if os(macOS)
                    .toolbar(removing: .title)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif

#if os(macOS) || os(visionOS)
                    .frame(minWidth: 600, maxWidth: .infinity, minHeight: 960, maxHeight: .infinity)
#endif
                    .preferredColorScheme(.dark)
            } else {
                NavigationView {
                    SettingsScreen(sessionManager: sessionManager)
                }
            }
        }
        #if !os(tvOS)
        .windowResizability(.contentSize)
        #endif

        #if os(macOS)
        Settings {
            SettingsScreen(sessionManager: sessionManager)
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
        let userDefaults = UserDefaults.standard
        
        prepareDependencies {
            $0.defaultDatabase = try! appDatabase()
            $0.defaultAppStorage = userDefaults
        }
        
        let sessionManager = SessionManager()
        
        sessionManager.load(key: .activeSession)
        ImagePipeline.Configuration.isSignpostLoggingEnabled = true

        self.sessionManager = sessionManager
    }
}

/// A global log of events for the app.
private let logger = Logger()
