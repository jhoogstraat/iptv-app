//
//  ContentView.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
//

import SwiftUI
import Foundation

/// A view that presents the app's user interface.
struct ContentView: View {
    /// Keep track of tab view customizations in app storage.
#if !os(macOS) && !os(tvOS)
    @AppStorage("sidebarCustomizations") var tabViewCustomization: TabViewCustomization
#endif
    
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ActiveSession.self) private var session
    
    @State private var selectedTab: Tabs = .home
    
    var body: some View {
            TabView(selection: $selectedTab) {
                Tab(Tabs.home.name, systemImage: Tabs.home.symbol, value: .home) {
                    ScopedPlaceholderView(
                        title: "For You In Progress",
                        message: "The personalized landing screen is being migrated to SQLiteData."
                    )
                }
                .customizationID(Tabs.home.customizationID)
#if !os(macOS) && !os(tvOS)
                .customizationBehavior(.disabled, for: .sidebar, .tabBar)
#endif
                
                Tab(value: Tabs.search, role: .search) {
                    SearchScreen()
                }
                .customizationID(Tabs.search.customizationID)
#if !os(macOS) && !os(tvOS)
                .customizationBehavior(.disabled, for: .sidebar, .tabBar)
#endif
                
                TabSection("Watch") {
                    Tab(Tabs.movies.name, systemImage: Tabs.movies.symbol, value: Tabs.movies) {
                        ScopedPlaceholderView(
                            title: "Movies In Progress",
                            message: "The movies browser is being migrated to SQLiteData."
                        )
                    }
                    .customizationID(Tabs.movies.customizationID)
                    
                    Tab(Tabs.series.name, systemImage: Tabs.series.symbol, value: Tabs.series) {
                        ScopedPlaceholderView(
                            title: "Series In Progress",
                            message: "The series browser is being migrated to SQLiteData."
                        )
                    }
                    .customizationID(Tabs.series.customizationID)
                    
                    Tab(Tabs.live.name, systemImage: Tabs.live.symbol, value: Tabs.live) {
                        ScopedPlaceholderView(
                            title: "Live TV Is Out of Scope",
                            message: "Live channels are not included in the current MVP release."
                        )
                    }
                    .customizationID(Tabs.live.customizationID)
                }
                
                TabSection("Library") {
                    Tab(Tabs.favorites.name, systemImage: Tabs.favorites.symbol, value: Tabs.favorites) {
                        ScopedPlaceholderView(
                            title: "Favorites In Progress",
                            message: "Favorites are being migrated to SQLiteData."
                        )
                    }
                    .customizationID(Tabs.favorites.customizationID)
                    
                    Tab(Tabs.downloads.name, systemImage: Tabs.downloads.symbol, value: Tabs.downloads) {
                        DownloadsScreen()
                    }
                    .customizationID(Tabs.downloads.customizationID)
                }
                
//#if !os(macOS)
                TabSection("Settings") {
                    Tab(Tabs.settings.name, systemImage: Tabs.settings.symbol, value: Tabs.settings) {
                        NavigationStack {
                            SettingsScreen(sessionManager: sessionManager)
                        }
                    }
                    .customizationID(Tabs.settings.customizationID)
                }
//#endif
            }
            .tabViewStyle(.sidebarAdaptable)
#if !os(macOS) && !os(tvOS)
            .tabViewCustomization($tabViewCustomization)
#endif
#if os(macOS)
            .overlay(alignment: .bottomTrailing) {
                // TODO: Activity view indicator
            }
#endif

    }
}

#Preview {
    ContentView()
}
