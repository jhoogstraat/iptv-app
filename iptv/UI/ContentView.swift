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
    
    @State private var selectedTab: Tabs = .home
   
    /// Keep track of tab view customizations in app storage.
#if !os(macOS) && !os(tvOS)
    @AppStorage("sidebarCustomizations") var tabViewCustomization: TabViewCustomization
#endif
    
    var body: some View {
            TabView(selection: $selectedTab) {
                Tab(Tabs.home.name, systemImage: Tabs.home.symbol, value: .home) {
                    ForYouScreen()
                        .requireSessionOrElse {
                            ContentUnavailableView {
                                Label("Quite empty in here", systemImage: "tray")
                            } description: {
                                Text("Add a provider to start syncing your library and build a local For You page.")
                            }
                        }
                }
                .customizationID(Tabs.home.customizationID)
#if !os(macOS) && !os(tvOS)
                .customizationBehavior(.disabled, for: .sidebar, .tabBar)
#endif
                
                Tab(value: Tabs.search, role: .search) {
                    SearchScreen()
                        .requireSessionOrElse {
                            ContentUnavailableView {
                                Label("No provider configured", systemImage: "magnifyingglass")
                            } description: {
                                Text("Add a provider to sync and search movies and series.")
                            }
                        }
                }
                .customizationID(Tabs.search.customizationID)
#if !os(macOS) && !os(tvOS)
                .customizationBehavior(.disabled, for: .sidebar, .tabBar)
#endif
                
                TabSection("Watch") {
                    Tab(Tabs.movies.name, systemImage: Tabs.movies.symbol, value: Tabs.movies) {
                        NavigationStack {
                            BrowseScreen(type: .movie)
                                .requireSessionOrElse {
                                    ContentUnavailableView {
                                        Label("Quite empty in here", systemImage: "tray")
                                    } description: {
                                        Text("Add a provider to start syncing your library and browse movies.")
                                    }
                                }
                        }
                    }
                    .customizationID(Tabs.movies.customizationID)
                    
                    Tab(Tabs.series.name, systemImage: Tabs.series.symbol, value: Tabs.series) {
                        NavigationStack {
                            BrowseScreen(type: .series)
                                .requireSessionOrElse {
                                    ContentUnavailableView {
                                        Label("Quite empty in here", systemImage: "tray")
                                    } description: {
                                        Text("Add a provider to start syncing your library and browse series.")
                                    }
                                }
                        }
                    }
                    .customizationID(Tabs.series.customizationID)
                    
                    Tab(Tabs.live.name, systemImage: Tabs.live.symbol, value: Tabs.live) {
                        LiveScreen()
                            .requireSessionOrElse {
                                ContentUnavailableView {
                                    Label("No provider configured", systemImage: "dot.radiowaves.left.and.right")
                                } description: {
                                    Text("Add a provider to sync live categories and play channels.")
                                }
                            }
                    }
                    .customizationID(Tabs.live.customizationID)
                }
                
                TabSection("Library") {
                    Tab(Tabs.favorites.name, systemImage: Tabs.favorites.symbol, value: Tabs.favorites) {
                        FavoritesScreen()
                            .requireSessionOrElse {
                                ContentUnavailableView {
                                    Label("No provider configured", systemImage: "heart")
                                } description: {
                                    Text("Add a provider to save and browse local favorites.")
                                }
                            }
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
                        SettingsScreen()
                    }
                    .customizationID(Tabs.settings.customizationID)
                }
//#endif
            }
            .tabViewStyle(.sidebarAdaptable)
#if !os(macOS) && !os(tvOS)
            .tabViewCustomization($tabViewCustomization)
#endif

    }
}

#Preview {
    ContentView()
        .environment(ProviderManager())
}
