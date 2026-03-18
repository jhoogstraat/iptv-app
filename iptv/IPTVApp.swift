//
//  IPTVApp.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
//

import SwiftUI
import SwiftData
import OSLog
import Nuke

@main
struct IPTVApp: App {
    /// An object that manages the model storage configuration.
    private let modelContainer: ModelContainer
    
    private let sessionManager: SessionManager
    
    var body: some Scene {
        WindowGroup {
            if let session = sessionManager.session {
                ContentView()
                    .environment(session)
                    .modelContainer(modelContainer)
#if os(macOS)
                    .toolbar(removing: .title)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif

#if os(macOS) || os(visionOS)
                    .frame(minWidth: 600, maxWidth: .infinity, minHeight: 960, maxHeight: .infinity)
#endif
                    .preferredColorScheme(.dark)
            } else {
                Text("Login Screen")
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
        let modelContainer = try! AppPersistence.makeModelContainer(isStoredInMemoryOnly: false)
        let sessionManager = SessionManager(userDefaults: UserDefaults.standard, modelContainer: modelContainer)
        
        sessionManager.load(key: .activeSession)
        ImagePipeline.Configuration.isSignpostLoggingEnabled = true
        
        self.modelContainer = modelContainer
        self.sessionManager = sessionManager
    }
}

/// A global log of events for the app.
let logger = Logger()
