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
            OnboardingShellView(sessionManager: sessionManager)
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
        
        sessionManager.load()
        ImagePipeline.Configuration.isSignpostLoggingEnabled = true

        self.sessionManager = sessionManager
    }
}

private struct OnboardingShellView: View {
    let sessionManager: SessionManager

    @State private var isPresentingProviderSetup = false
    @State private var performedInitialPresentationCheck = false

    var body: some View {
        Group {
            if let session = sessionManager.session {
                ContentView(presentProviderSetup: presentProviderSetup)
                    .environment(session)
            } else {
                ContentView(presentProviderSetup: presentProviderSetup)
            }
        }
        .environment(sessionManager)
        .popover(isPresented: $isPresentingProviderSetup) {
            ProviderSetupPopover(sessionManager: sessionManager)
        }
        .onAppear {
            guard !performedInitialPresentationCheck else { return }
            performedInitialPresentationCheck = true
            if !sessionManager.hasActiveSession {
                isPresentingProviderSetup = true
            }
        }
        .onChange(of: sessionManager.hasActiveSession) { _, hasActiveSession in
            if hasActiveSession {
                isPresentingProviderSetup = false
            }
        }
    }

    private func presentProviderSetup() {
        isPresentingProviderSetup = true
    }
}

/// A global log of events for the app.
private let logger = Logger()
