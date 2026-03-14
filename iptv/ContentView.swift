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
    @Environment(Catalog.self) private var catalog
    @Environment(BackgroundActivityCenter.self) private var backgroundActivityCenter
    @Environment(ProviderStore.self) private var providerStore
    @State private var selectedTab: Tabs = ProcessInfo.processInfo.arguments.contains("--uitest-open-movies") ? .movies : .home
    @State private var isShowingUITestSettings = false

    private var isUITestOpenMovies: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-open-movies")
    }
    
    var body: some View {
        Group {
            if isUITestOpenMovies {
                if providerStore.hasConfiguration {
                    MoviesScreen()
                } else {
                    uiTestMissingProviderView
                }
            } else {
                TabView(selection: $selectedTab) {
                    Tab(Tabs.home.name, systemImage: Tabs.home.symbol, value: .home) {
                        ForYouScreen()
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
                            MoviesScreen()
                        }
                        .customizationID(Tabs.movies.customizationID)

                        Tab(Tabs.series.name, systemImage: Tabs.series.symbol, value: Tabs.series) {
                            MoviesScreen(contentType: .series)
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
                            LibraryScreen()
                        }
                        .customizationID(Tabs.favorites.customizationID)

                        Tab(Tabs.downloads.name, systemImage: Tabs.downloads.symbol, value: Tabs.downloads) {
                            DownloadsScreen()
                        }
                        .customizationID(Tabs.downloads.customizationID)
                    }

                    #if !os(macOS)
                    TabSection("Settings") {
                        Tab(Tabs.settings.name, systemImage: Tabs.settings.symbol, value: Tabs.settings) {
                            NavigationStack {
                                SettingsScreen()
                            }
                        }
                        .customizationID(Tabs.settings.customizationID)
                    }
                    #endif
                }
                .tabViewStyle(.sidebarAdaptable)
                #if !os(macOS) && !os(tvOS)
                .tabViewCustomization($tabViewCustomization)
                #endif
            }
        }
        .withVideoPlayer()
        #if os(macOS)
        .overlay(alignment: .bottomTrailing) {
            BackgroundActivityIndicatorView(activityCenter: backgroundActivityCenter)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        #endif
        .task(id: providerStore.revision) {
            guard providerStore.hasConfiguration else {
                await catalog.stopBackgroundRefreshing()
                return
            }
            await catalog.startBackgroundRefreshing()
        }
    }

    private var uiTestMissingProviderView: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "key.horizontal.fill")
                    .font(.largeTitle)
                Text("Configure Provider")
                    .font(.title3.weight(.semibold))
                Text("Add your provider credentials in Settings before browsing movies.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button("Configure Provider") {
                    isShowingUITestSettings = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Movies")
        }
        .sheet(isPresented: $isShowingUITestSettings) {
            NavigationStack {
                SettingsScreen()
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                isShowingUITestSettings = false
                            }
                        }
                    }
            }
            .environment(providerStore)
        }
    }
}

#Preview(traits: .previewData) {
    ContentView()
}
