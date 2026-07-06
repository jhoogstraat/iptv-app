//
//  LibraryScreen.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import SwiftUI
import SQLiteData

struct FavoritesScreen: View {
    private enum FavoriteScope: String, CaseIterable, Identifiable {
        case all
        case movies
        case series
        case episodes

        var id: Self { self }

        var title: String {
            switch self {
            case .all: "All"
            case .movies: "Movies"
            case .series: "Series"
            case .episodes: "Episodes"
            }
        }

        func includes(_ mediaType: MediaType) -> Bool {
            switch self {
            case .all:
                mediaType == .movie || mediaType == .series || mediaType == .episode
            case .movies:
                mediaType == .movie
            case .series:
                mediaType == .series
            case .episodes:
                mediaType == .episode
            }
        }
    }

    private struct FavoriteSection: Identifiable {
        let mediaType: MediaType
        let items: [FavoriteItem]

        var id: Int { mediaType.rawValue }
        var title: String {
            switch mediaType {
            case .movie: "Movies"
            case .series: "Series"
            case .episode: "Episodes"
            case .live: "Live"
            }
        }
    }

    @Environment(Session.self) private var session
    @FetchAll private var favorites: [Favorite]
    @FetchAll private var media: [Media]
    @State private var scope: FavoriteScope = .all

    private var scopedFavorites: [FavoriteItem] {
        let mediaByKey = Dictionary(
            media.map { (FavoriteStore.contentKey(mediaType: $0.type, sourceID: $0.sourceID), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return favorites
            .filter { $0.providerID == session.providerID && scope.includes($0.mediaType) }
            .sorted(by: FavoriteStore.favoriteOrdering)
            .map { favorite in
                FavoriteItem(
                    favorite: favorite,
                    media: mediaByKey[FavoriteStore.contentKey(mediaType: favorite.mediaType, sourceID: favorite.sourceID)]
                )
            }
    }

    private var sections: [FavoriteSection] {
        let order: [MediaType] = [.movie, .series, .episode, .live]
        return order.compactMap { mediaType in
            let items = scopedFavorites.filter { $0.mediaType == mediaType }
            return items.isEmpty ? nil : FavoriteSection(mediaType: mediaType, items: items)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Favorite type", selection: $scope) {
                    ForEach(FavoriteScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                content
            }
            .navigationTitle("Favorites")
        }
    }

    @ViewBuilder
    private var content: some View {
        if favorites.filter({ $0.providerID == session.providerID }).isEmpty {
            ContentUnavailableView {
                Label("No favorites yet", systemImage: "heart")
            } description: {
                Text("Add movies, series, or episodes from details or the player. Favorites are stored locally for the active provider.")
            }
        } else if scopedFavorites.isEmpty {
            ContentUnavailableView {
                Label("No \(scope.title.lowercased()) favorites", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Choose another favorite type or add more items from detail screens.")
            }
        } else {
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            favoriteRow(for: item)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func favoriteRow(for item: FavoriteItem) -> some View {
        if let media = item.media {
            NavigationLink {
                MediaDetailDestination(media: media, categoryTitle: item.categoryTitle)
            } label: {
                FavoriteRow(item: item)
            }
            .swipeActions {
                Button(role: .destructive) {
                    FavoriteStore.remove(item.favorite)
                } label: {
                    Label("Remove", systemImage: "heart.slash")
                }
            }
        } else {
            FavoriteRow(item: item)
                .swipeActions {
                    Button(role: .destructive) {
                        FavoriteStore.remove(item.favorite)
                    } label: {
                        Label("Remove", systemImage: "heart.slash")
                    }
                }
        }
    }
}

private struct FavoriteRow: View {
    let item: FavoriteItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.artworkURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(Color.secondary.opacity(0.16))
                        Image(systemName: systemImage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 54, height: 78)
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Label(typeTitle, systemImage: systemImage)
                        .labelStyle(.titleAndIcon)

                    if let categoryTitle = item.categoryTitle, !categoryTitle.isEmpty {
                        Text("•")
                        Text(categoryTitle)
                            .lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !item.isAvailableLocally {
                    Text("Unavailable in the current local catalog snapshot")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var typeTitle: String {
        switch item.mediaType {
        case .movie: "Movie"
        case .series: "Series"
        case .episode: "Episode"
        case .live: "Live"
        }
    }

    private var systemImage: String {
        switch item.mediaType {
        case .movie: "film"
        case .series: "tv"
        case .episode: "play.rectangle"
        case .live: "dot.radiowaves.left.and.right"
        }
    }
}

#Preview {
    FavoritesScreen()
}
