//
//  LibraryScreen.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import SwiftUI

struct FavoritesScreen: View {
    @Environment(ActiveSession.self) private var session
    
    @Query private var favorites: [Media]
    @Query private var continueWatching: [WatchActivity]
    
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
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
                Text("Configure Provider")
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
                                    ForEach(continueWatching) { activity in
                                        NavigationLink {
                                            destination(for: activity.media)
                                        } label: {
                                            Text("TODO")
//                                            ContinueWatchingCardView(
//                                                item: ForYouItem.from(video: video, progress: record.progress)
//                                            )
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
                                NavigationLink {
                                    destination(for: favorite)
                                } label: {
                                    HStack(spacing: 12) {
                                        VideoTile(media: favorite)
                                            .frame(width: 70, height: 100)
                                            .clipShape(.rect(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(favorite.name)
                                                .font(.headline)
                                                .lineLimit(2)
                                            Text("TODO: Series or Movie")
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
    private func destination(for media: Media) -> some View {
        switch media.self {
            case is Movie:
                MovieDetailScreen(movie: media as! Movie)
        case is Series:
                EpisodeDetailTile(series: media as! Series, episode: (media as! Series).episodes.first!)
                .navigationTitle(media.name)
        default:
            ScopedPlaceholderView(
                title: "Live Episodes Are Unavailable",
                message: "Episode detail only applies to series content."
            )
                .navigationTitle(media.name)
        }
    }
}

#Preview(traits: .previewData) {
    FavoritesScreen()
}
