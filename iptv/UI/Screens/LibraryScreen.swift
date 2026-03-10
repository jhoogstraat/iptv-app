//
//  LibraryScreen.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import SwiftUI

struct LibraryScreen: View {
    @Environment(ProviderStore.self) private var providerStore
    @Environment(FavoritesStore.self) private var favoritesStore

    @State private var favorites: [FavoriteRecord] = []
    @State private var continueWatching: [WatchActivityRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var reloadToken: String {
        "\(providerStore.revision)|\(favoritesStore.revision)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if !providerStore.hasConfiguration {
                    missingProviderView
                } else if isLoading {
                    ProgressView()
                } else {
                    content
                }
            }
            .navigationTitle("Library")
        }
        .task(id: reloadToken) {
            await loadData()
        }
    }

    private var missingProviderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal.fill")
                .font(.largeTitle)
            Text("Configure Provider")
                .font(.title3.weight(.semibold))
            Text("Add provider credentials in Settings to use Library.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            #if os(macOS)
            SettingsLink {
                Text("Open Settings")
            }
                .buttonStyle(.borderedProminent)
            #endif
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if favorites.isEmpty && continueWatching.isEmpty {
            ContentUnavailableView(
                "Library Is Empty",
                systemImage: "books.vertical",
                description: Text("Favorite titles or start watching to build your library.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if !continueWatching.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Continue Watching")
                                .font(.headline)
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 14) {
                                    ForEach(continueWatching.prefix(20), id: \.key) { record in
                                        let video = record.asVideo()
                                        NavigationLink {
                                            destination(for: video)
                                        } label: {
                                            ContinueWatchingCardView(
                                                item: ForYouItem.from(video: video, progress: record.progress)
                                            )
                                            .frame(width: 170)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .scrollIndicators(.never)
                        }
                    }

                    if !favorites.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Favorites")
                                .font(.headline)
                            ForEach(favorites, id: \.id) { favorite in
                                let video = favorite.asVideo()
                                NavigationLink {
                                    destination(for: video)
                                } label: {
                                    HStack(spacing: 12) {
                                        VideoTile(video: video)
                                            .frame(width: 70, height: 100)
                                            .clipShape(.rect(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(video.name)
                                                .font(.headline)
                                                .lineLimit(2)
                                            Text(video.xtreamContentType == .series ? "Series" : "Movie")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func destination(for video: Video) -> some View {
        switch video.xtreamContentType {
        case .vod:
            MovieDetailScreen(video: video)
        case .series:
            EpisodeDetailTile(video: video)
                .navigationTitle(video.name)
        case .live:
            ScopedPlaceholderView(
                title: "Live Episodes Are Unavailable",
                message: "Episode detail only applies to series content."
            )
                .navigationTitle(video.name)
        }
    }

    private func loadData() async {
        guard providerStore.hasConfiguration else {
            favorites = []
            continueWatching = []
            errorMessage = nil
            return
        }

        do {
            isLoading = true
            errorMessage = nil

            let config = try providerStore.requiredConfiguration()
            let providerFingerprint = ProviderCacheFingerprint.make(from: config)

            async let favoriteData = favoritesStore.load(providerFingerprint: providerFingerprint)
            async let watchData = DiskWatchActivityStore.shared.loadAll()

            let loadedFavorites = await favoriteData
            let loadedWatchRecords = await watchData.filter { $0.providerFingerprint == providerFingerprint }

            favorites = loadedFavorites
            continueWatching = loadedWatchRecords.filter { !$0.isCompleted && $0.progressFraction >= 0.05 }
            isLoading = false
        } catch {
            favorites = []
            continueWatching = []
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}

#Preview(traits: .previewData) {
    LibraryScreen()
}
