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

    var body: some View {
        NavigationStack {
            Group {
                if !providerStore.hasConfiguration {
                    ContentUnavailableView(
                        "Configure Provider",
                        systemImage: "key.horizontal.fill",
                        description: Text("Add provider credentials in Settings to use Library.")
                    )
                } else if isLoading {
                    ProgressView()
                } else {
                    content
                }
            }
            .navigationTitle("Library")
        }
        .task(id: providerStore.revision) {
            await loadData()
        }
        .task(id: favoritesStore.revision) {
            await loadData()
        }
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
        case .series, .live:
            EpisodeDetailTile()
                .navigationTitle(video.name)
        }
    }

    private func loadData() async {
        guard providerStore.hasConfiguration else {
            favorites = []
            continueWatching = []
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

