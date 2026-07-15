//
//  LibraryScreen.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import SwiftUI
import SQLiteData

enum FavoritesFocusProjection {
    nonisolated static func successor(
        afterRemoving removedID: Favorite.ID,
        from visibleIDs: [Favorite.ID]
    ) -> Favorite.ID? {
        guard let removedIndex = visibleIDs.firstIndex(of: removedID) else {
            return visibleIDs.first
        }

        let nextIndex = visibleIDs.index(after: removedIndex)
        if nextIndex < visibleIDs.endIndex {
            return visibleIDs[nextIndex]
        }
        guard removedIndex > visibleIDs.startIndex else { return nil }
        return visibleIDs[visibleIDs.index(before: removedIndex)]
    }
}

struct FavoritesScreen: View {
    @AppStorage(UserProfileStore.revisionKey) private var profileRevision = 0
    private enum FavoriteScope: String, CaseIterable, Identifiable {
        case all
        case movies
        case series
        case episodes
        case live

        var id: Self { self }

        var title: String {
            switch self {
            case .all: "All"
            case .movies: "Movies"
            case .series: "Series"
            case .episodes: "Episodes"
            case .live: "Live"
            }
        }

        func includes(_ mediaType: MediaType) -> Bool {
            switch self {
            case .all:
                mediaType == .movie || mediaType == .series || mediaType == .episode || mediaType == .live
            case .movies:
                mediaType == .movie
            case .series:
                mediaType == .series
            case .episodes:
                mediaType == .episode
            case .live:
                mediaType == .live
            }
        }
    }

    private enum FavoriteFocusTarget: Hashable {
        case scope(FavoriteScope)
        case content(Favorite.ID)
        case remove(Favorite.ID)
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

    private struct RemovalFailure: Identifiable {
        let message: String
        var id: String { message }
    }

    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FetchAll private var favorites: [Favorite]
    @FetchAll private var media: [Media]
    @FetchAll private var categories: [Category]
    @State private var scope: FavoriteScope = .all
    @State private var removalFailure: RemovalFailure?
    @FocusState private var focusedTarget: FavoriteFocusTarget?

    private var scopedFavorites: [FavoriteItem] {
        let mediaByKey = Dictionary(
            media.map { (FavoriteStore.contentKey(mediaType: $0.type, sourceID: $0.sourceID), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let categoryByID = Dictionary(
            categories.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return favorites
            .filter { $0.profileID == session.activeProfileID && $0.providerID == session.providerID && scope.includes($0.mediaType) }
            .sorted(by: FavoriteStore.favoriteOrdering)
            .map { favorite in
                let localMedia = mediaByKey[
                    FavoriteStore.contentKey(mediaType: favorite.mediaType, sourceID: favorite.sourceID)
                ]
                let currentCategory = localMedia
                    .flatMap(\.categoryID)
                    .flatMap { categoryByID[$0] }
                return FavoriteItem(
                    favorite: favorite,
                    media: localMedia,
                    category: currentCategory
                )
            }
    }

    private var sections: [FavoriteSection] {
        let order: [MediaType] = [.movie, .series, .episode, .live]
        let items = scopedFavorites
        return order.compactMap { mediaType in
            let sectionItems = items.filter { $0.mediaType == mediaType }
            return sectionItems.isEmpty ? nil : FavoriteSection(mediaType: mediaType, items: sectionItems)
        }
    }

    private var visibleFavoriteIDs: [Favorite.ID] {
        sections.flatMap(\.items).map(\.id)
    }

    private var usesScrollableScopeSelector: Bool {
        horizontalSizeClass == .compact || dynamicTypeSize >= .xLarge
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scopeSelector
                content
            }
            .navigationTitle("Favorites")
        }
        .alert(item: $removalFailure) { failure in
            Alert(
                title: Text("Couldn’t Remove Favorite"),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var scopeSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Show favorites")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if usesScrollableScopeSelector {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FavoriteScope.allCases) { candidate in
                            Button {
                                scope = candidate
                            } label: {
                                Text(candidate.title)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(scope == candidate ? .accentColor : .secondary)
                            .background {
                                if scope == candidate {
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.16))
                                }
                            }
                            .accessibilityLabel("\(candidate.title) favorites")
                            .accessibilityAddTraits(scope == candidate ? .isSelected : [])
                            .accessibilityHint("Shows \(candidate.title.lowercased()) favorites")
                            .focused($focusedTarget, equals: .scope(candidate))
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                Picker("Favorite type", selection: $scope) {
                    ForEach(FavoriteScope.allCases) { candidate in
                        Text(candidate.title).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .accessibilityLabel("Favorite type")
                .accessibilityValue(scope.title)
                .focused($focusedTarget, equals: .scope(scope))
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if favorites.filter({ $0.profileID == session.activeProfileID && $0.providerID == session.providerID }).isEmpty {
            ContentUnavailableView {
                Label("No favorites yet", systemImage: "heart")
            } description: {
                Text("Add movies, series, episodes, or live channels from details, Live, or the player. Favorites are stored locally for the active provider.")
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
            if media.type == .live {
                removableRow(for: item) {
                    liveFavoriteButton(for: item, media: media)
                }
            } else {
                removableRow(for: item) {
                    NavigationLink {
                        MediaDetailDestination(media: media, categoryTitle: item.categoryTitle)
                    } label: {
                        FavoriteRow(
                            item: item,
                            isFocused: focusedTarget == .content(item.id)
                        )
                    }
                    .focused($focusedTarget, equals: .content(item.id))
                    .accessibilityHint("Shows details for \(item.title)")
                }
            }
        } else {
            removableRow(for: item) {
                unavailableFavoriteRow(for: item)
            }
        }
    }

    @ViewBuilder
    private func liveFavoriteButton(for item: FavoriteItem, media: Media) -> some View {
        let button = Button {
            player.load(media, presentation: .fullWindow)
        } label: {
            FavoriteRow(
                item: item,
                isFocused: focusedTarget == .content(item.id)
            )
        }
        .focused($focusedTarget, equals: .content(item.id))
        .accessibilityLabel("Play \(item.title)")
        .accessibilityHint("Starts live playback")

#if os(tvOS)
        button
#else
        button.buttonStyle(.plain)
#endif
    }

    @ViewBuilder
    private func unavailableFavoriteRow(for item: FavoriteItem) -> some View {
#if os(macOS)
        FavoriteRow(
            item: item,
            isFocused: focusedTarget == .content(item.id)
        )
        .focusable()
        .focused($focusedTarget, equals: .content(item.id))
        .accessibilityHint("Press Delete or open the context menu to remove this unavailable favorite")
#else
        FavoriteRow(item: item)
#endif
    }

    @ViewBuilder
    private func removableRow<Content: View>(
        for item: FavoriteItem,
        @ViewBuilder content: () -> Content
    ) -> some View {
#if os(iOS)
        content()
            .swipeActions {
                removalButton(for: item)
            }
#elseif os(macOS)
        content()
            .contextMenu {
                removalButton(for: item)
                    .keyboardShortcut(.delete, modifiers: [])
            }
            .onDeleteCommand {
                removeFavorite(item)
            }
#elseif os(tvOS)
        HStack(spacing: 16) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            removalButton(for: item)
                .buttonStyle(.bordered)
                .tint(.red)
                .focused($focusedTarget, equals: .remove(item.id))
        }
#else
        content()
            .contextMenu {
                removalButton(for: item)
            }
#endif
    }

    private func removalButton(for item: FavoriteItem) -> some View {
        Button(role: .destructive) {
            removeFavorite(item)
        } label: {
            Label("Remove", systemImage: "heart.slash")
        }
        .accessibilityLabel("Remove \(item.title) from Favorites")
        .accessibilityHint("Removes this item from the active provider’s favorites")
    }

    private func removeFavorite(_ item: FavoriteItem) {
        let successorID = FavoritesFocusProjection.successor(
            afterRemoving: item.id,
            from: visibleFavoriteIDs
        )

        do {
            switch try FavoriteStore.remove(item.favorite) {
            case .removed:
                moveFocusAfterRemoval(to: successorID)
            case .added:
                removalFailure = RemovalFailure(
                    message: "\(item.title) was not removed. Please try again."
                )
            }
        } catch {
            removalFailure = RemovalFailure(message: error.localizedDescription)
        }
    }

    private func moveFocusAfterRemoval(to successorID: Favorite.ID?) {
#if os(tvOS)
        scheduleFocus(successorID.map(FavoriteFocusTarget.remove) ?? .scope(scope))
#elseif os(macOS)
        scheduleFocus(successorID.map(FavoriteFocusTarget.content) ?? .scope(scope))
#endif
    }

    private func scheduleFocus(_ target: FavoriteFocusTarget) {
        focusedTarget = nil
        Task { @MainActor in
            await Task.yield()
            focusedTarget = target
        }
    }
}

private struct FavoriteRow: View {
    let item: FavoriteItem
    var isFocused = false

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
        .background(
            isFocused ? Color.accentColor.opacity(0.12) : Color.clear,
            in: .rect(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.accentColor : .clear, lineWidth: 3)
        }
        .animation(.easeOut(duration: 0.16), value: isFocused)
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
