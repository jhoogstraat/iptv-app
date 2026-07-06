//
//  ForYouScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import SQLiteData

struct ForYouScreen: View {
    fileprivate struct ContinueWatchingEntry: Identifiable {
        let activity: WatchActivity
        let media: Media

        var id: WatchActivity.ID { activity.id }
    }

    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @AppStorage(CategoryPrefixVisibilityStore.revisionKey) private var prefixVisibilityRevision = 0
    @AppStorage(FavoriteStore.revisionKey) private var favoritesRevision = 0

    @FetchAll(Category.where { $0.type.eq(MediaType.movie).or($0.type.eq(MediaType.series)).or($0.type.eq(MediaType.episode)) }) private var categories: [Category]
    @FetchAll(Media.where { $0.type.eq(MediaType.movie).or($0.type.eq(MediaType.series)).or($0.type.eq(MediaType.episode)) }) private var media: [Media]
    @FetchAll(WatchActivity.where { $0.completed.eq(false) }) private var watchActivities: [WatchActivity]
    @FetchAll private var favorites: [Favorite]

    @State private var selectedDetail: Media?

    private var hiddenGroupKeys: Set<String> {
        _ = prefixVisibilityRevision
        return CategoryPrefixVisibilityStore.hiddenGroupKeys(for: session.providerID)
    }

    private var categoryByID: [Category.ID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    private var mediaByKey: [String: Media] {
        Dictionary(
            media.map { (FavoriteStore.contentKey(mediaType: $0.type, sourceID: $0.sourceID), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var visibleCatalogMedia: [Media] {
        media.filter(isVisibleCatalogMedia)
    }

    private var continueWatchingEntries: [ContinueWatchingEntry] {
        Array(
            watchActivities
                .filter { $0.providerID == session.providerID && $0.isResumeEligible }
                .sorted(by: watchActivityOrdering)
                .compactMap { activity -> ContinueWatchingEntry? in
                    guard let media = mediaByKey[FavoriteStore.contentKey(mediaType: activity.mediaType, sourceID: activity.sourceID)],
                          isVisibleCatalogMedia(media)
                    else { return nil }
                    return ContinueWatchingEntry(activity: activity, media: media)
                }
                .prefix(20)
        )
    }

    private var favoriteRailMedia: [Media] {
        _ = favoritesRevision
        return Array(
            favorites
                .filter { $0.providerID == session.providerID }
                .sorted(by: FavoriteStore.favoriteOrdering)
                .compactMap { favorite in
                    mediaByKey[FavoriteStore.contentKey(mediaType: favorite.mediaType, sourceID: favorite.sourceID)]
                }
                .filter(isVisibleCatalogMedia)
                .prefix(20)
        )
    }

    private var topRatedMovies: [Media] {
        Array(
            visibleCatalogMedia
                .filter { $0.type == .movie && $0.rating != nil }
                .sorted { LibraryFilterEngine.ordered($0, before: $1, by: .rating) }
                .prefix(20)
        )
    }

    private var topRatedSeries: [Media] {
        Array(
            visibleCatalogMedia
                .filter { $0.type == .series && $0.rating != nil }
                .sorted { LibraryFilterEngine.ordered($0, before: $1, by: .rating) }
                .prefix(20)
        )
    }

    private var recentlyUpdated: [Media] {
        Array(
            visibleCatalogMedia
                .filter { $0.type == .movie || $0.type == .series }
                .sorted { LibraryFilterEngine.ordered($0, before: $1, by: .newest) }
                .prefix(20)
        )
    }

    private var heroItem: Media? {
        continueWatchingEntries.first?.media
            ?? favoriteRailMedia.first
            ?? topRatedMovies.first
            ?? topRatedSeries.first
            ?? recentlyUpdated.first
    }

    private var hasAnyRailContent: Bool {
        !continueWatchingEntries.isEmpty
            || !favoriteRailMedia.isEmpty
            || !topRatedMovies.isEmpty
            || !topRatedSeries.isEmpty
            || !recentlyUpdated.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if let heroItem {
                        ForYouHeroView(
                            item: heroItem,
                            onPlay: { playOrOpen(heroItem) },
                            onDetails: { selectedDetail = heroItem }
                        )
                    }

                    if !hasAnyRailContent {
                        emptyState
                    } else {
                        rails
                    }
                }
                .padding()
            }
            .navigationTitle("For You")
            .navigationDestination(item: $selectedDetail) { media in
                MediaDetailDestination(media: media, categoryTitle: categoryTitle(for: media))
            }
        }
    }

    @ViewBuilder
    private var rails: some View {
        if !continueWatchingEntries.isEmpty {
            ContinueWatchingRail(entries: continueWatchingEntries, categoryTitle: categoryTitle(for:))
        }

        if !favoriteRailMedia.isEmpty {
            ForYouRailView(
                title: "Favorites",
                subtitle: "Pinned from your persisted local favorites.",
                items: favoriteRailMedia,
                badge: { _ in nil }
            ) { media in
                MediaDetailDestination(media: media, categoryTitle: categoryTitle(for: media))
            }
        }

        if !topRatedMovies.isEmpty {
            ForYouRailView(
                title: "Top Rated Movies",
                subtitle: "Highest rated local movie rows in visible categories.",
                items: topRatedMovies,
                badge: { _ in nil }
            ) { media in
                MediaDetailDestination(media: media, categoryTitle: categoryTitle(for: media))
            }
        }

        if !topRatedSeries.isEmpty {
            ForYouRailView(
                title: "Top Rated Series",
                subtitle: "Highest rated local series rows in visible categories.",
                items: topRatedSeries,
                badge: { _ in .series }
            ) { media in
                MediaDetailDestination(media: media, categoryTitle: categoryTitle(for: media))
            }
        }

        if !recentlyUpdated.isEmpty {
            ForYouRailView(
                title: "Recently Updated",
                subtitle: "Newest local catalog updates after prefix visibility filters.",
                items: recentlyUpdated,
                badge: { isRecentlyAdded($0) ? .new : nil }
            ) { media in
                MediaDetailDestination(media: media, categoryTitle: categoryTitle(for: media))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptySystemImage)
        } description: {
            Text(emptyDescription)
        } actions: {
            if !hiddenGroupKeys.isEmpty {
                Button("Clear Prefix Visibility") {
                    CategoryPrefixVisibilityStore.setHiddenGroupKeys([], for: session.providerID)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var emptyTitle: String {
        if media.isEmpty { return "No local catalog yet" }
        if !hiddenGroupKeys.isEmpty && visibleCatalogMedia.isEmpty { return "All visible catalog rows are hidden" }
        return "Nothing to recommend yet"
    }

    private var emptySystemImage: String {
        if media.isEmpty { return "folder.badge.questionmark" }
        if !hiddenGroupKeys.isEmpty && visibleCatalogMedia.isEmpty { return "line.3.horizontal.decrease.circle" }
        return "sparkles"
    }

    private var emptyDescription: String {
        if media.isEmpty {
            return "Sync and open Movies or Series categories to hydrate local rows. For You only uses local catalog, watch activity, and favorites."
        }
        if !hiddenGroupKeys.isEmpty && visibleCatalogMedia.isEmpty {
            return "Prefix visibility settings hide every local row that could be used for deterministic discovery."
        }
        return "Watch something, add favorites, or sync rows with ratings and update dates to populate local rails."
    }

    private func isVisibleCatalogMedia(_ media: Media) -> Bool {
        LibraryFilterEngine.matches(
            media,
            categoryByID: categoryByID,
            state: LibraryFilterState(),
            hiddenGroupKeys: hiddenGroupKeys
        )
    }

    private func categoryTitle(for media: Media) -> String? {
        guard let categoryID = media.categoryID else { return nil }
        return categoryByID[categoryID]?.title
    }

    private func playOrOpen(_ media: Media) {
        if media.type == .movie || media.type == .episode {
            player.load(media, presentation: .fullWindow)
        } else {
            selectedDetail = media
        }
    }

    private func watchActivityOrdering(_ lhs: WatchActivity, _ rhs: WatchActivity) -> Bool {
        if lhs.lastWatchedAt != rhs.lastWatchedAt {
            return lhs.lastWatchedAt > rhs.lastWatchedAt
        }
        if lhs.title.localizedStandardCompare(rhs.title) != .orderedSame {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.sourceID < rhs.sourceID
    }

    private func isRecentlyAdded(_ media: Media) -> Bool {
        media.updatedAt >= Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
    }
}

private struct ContinueWatchingRail: View {
    let entries: [ForYouScreen.ContinueWatchingEntry]
    let categoryTitle: (Media) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Continue Watching")
                    .font(.headline)
                Text("Unfinished local watch activity, sorted by last watched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(entries) { entry in
                        NavigationLink {
                            MediaDetailDestination(media: entry.media, categoryTitle: categoryTitle(entry.media))
                        } label: {
                            ContinueWatchingCardView(item: entry.media, activity: entry.activity)
                                .frame(width: 190)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.never)
        }
    }
}

#Preview {
    ForYouScreen()
}
