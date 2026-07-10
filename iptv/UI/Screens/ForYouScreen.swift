//
//  ForYouScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import SQLiteData

struct ForYouSnapshot {
    static let railLimit = 20

    struct ContinueWatchingEntry: Identifiable {
        let activity: WatchActivity
        let media: Media
        let progressDescription: String

        var id: WatchActivity.ID { activity.id }
    }

    enum HeroReason: Equatable {
        case continueWatching
        case favorite
        case topRatedMovie
        case topRatedSeries
        case recentlyUpdated

        var title: String {
            switch self {
            case .continueWatching: "Continue Watching"
            case .favorite: "From Your Favorites"
            case .topRatedMovie: "Top Rated Movie"
            case .topRatedSeries: "Top Rated Series"
            case .recentlyUpdated: "Recently Updated"
            }
        }
    }

    enum HeroAction: Equatable {
        case resume
        case play
        case browseEpisodes
        case details

        var title: String {
            switch self {
            case .resume: "Resume"
            case .play: "Play"
            case .browseEpisodes: "Browse Episodes"
            case .details: "Details"
            }
        }

        var systemImage: String {
            switch self {
            case .resume: "play.fill"
            case .play: "play.fill"
            case .browseEpisodes: "rectangle.stack.fill"
            case .details: "info.circle"
            }
        }
    }

    struct Hero {
        let media: Media
        let reason: HeroReason
        let activity: WatchActivity?
        let primaryAction: HeroAction
        let secondaryAction: HeroAction?
    }

    enum SparseState: Equatable {
        case loading
        case failed(String?)
        case unhydrated
        case allEmpty
        case allHidden
        case noRecommendations
    }

    let categoryByID: [Category.ID: Category]
    let continueWatching: [ContinueWatchingEntry]
    let favorites: [Media]
    let topRatedMovies: [Media]
    let topRatedSeries: [Media]
    let recentlyUpdated: [Media]
    let hero: Hero?
    let sparseState: SparseState?

    private let recentlyAddedMediaIDs: Set<Media.ID>

    init(
        providerID: Provider.ID,
        categories: [Category],
        media: [Media],
        watchActivities: [WatchActivity],
        favorites: [Favorite],
        hiddenGroupKeys: Set<String>,
        runtimeHydrationStates: [Category.ID: SyncManager.CategoryHydrationState],
        syncStatus: SyncManager.SyncStatus,
        syncErrorMessage: String?,
        now: Date = .now
    ) {
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        self.categoryByID = categoryByID

        var mediaByKey: [LibraryContentKey: Media] = [:]
        mediaByKey.reserveCapacity(media.count)
        for item in media {
            let key = LibraryContentKey(media: item)
            if mediaByKey[key] == nil {
                mediaByKey[key] = item
            }
        }

        var visibleMediaIDs = Set<Media.ID>()
        visibleMediaIDs.reserveCapacity(media.count)
        var topRatedMovies: [Media] = []
        var topRatedSeries: [Media] = []
        var recentlyUpdated: [Media] = []
        var recentlyAddedMediaIDs = Set<Media.ID>()
        let recentlyAddedThreshold = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now

        for item in media {
            guard LibraryFilterEngine.matches(
                item,
                categoryByID: categoryByID,
                state: LibraryFilterState(),
                hiddenGroupKeys: hiddenGroupKeys
            ) else {
                continue
            }

            visibleMediaIDs.insert(item.id)

            if item.updatedAt >= recentlyAddedThreshold {
                recentlyAddedMediaIDs.insert(item.id)
            }

            switch item.type {
            case .movie:
                if item.rating != nil {
                    Self.insertBounded(
                        item,
                        into: &topRatedMovies,
                        orderedBefore: Self.ratingOrdered
                    )
                }
                Self.insertBounded(
                    item,
                    into: &recentlyUpdated,
                    orderedBefore: Self.newestOrdered
                )
            case .series:
                if item.rating != nil {
                    Self.insertBounded(
                        item,
                        into: &topRatedSeries,
                        orderedBefore: Self.ratingOrdered
                    )
                }
                Self.insertBounded(
                    item,
                    into: &recentlyUpdated,
                    orderedBefore: Self.newestOrdered
                )
            case .episode, .live:
                break
            }
        }

        var continueWatching: [ContinueWatchingEntry] = []
        for activity in watchActivities where activity.providerID == providerID && activity.isResumeEligible {
            let key = LibraryContentKey(mediaType: activity.mediaType, sourceID: activity.sourceID)
            guard let item = mediaByKey[key],
                  Self.isDirectlyPlayable(item),
                  visibleMediaIDs.contains(item.id)
            else {
                continue
            }

            let entry = ContinueWatchingEntry(
                activity: activity,
                media: item,
                progressDescription: ForYouWatchProgress.description(for: activity)
            )
            Self.insertBounded(entry, into: &continueWatching) {
                WatchActivityStore.activityOrdering($0.activity, $1.activity)
            }
        }

        struct FavoriteEntry {
            let favorite: Favorite
            let media: Media
        }

        var favoriteEntries: [FavoriteEntry] = []
        for favorite in favorites where favorite.providerID == providerID {
            let key = LibraryContentKey(mediaType: favorite.mediaType, sourceID: favorite.sourceID)
            guard let item = mediaByKey[key], visibleMediaIDs.contains(item.id) else {
                continue
            }

            Self.insertBounded(
                FavoriteEntry(favorite: favorite, media: item),
                into: &favoriteEntries
            ) {
                FavoriteStore.favoriteOrdering($0.favorite, $1.favorite)
            }
        }
        let favoriteMedia = favoriteEntries.map(\.media)

        self.continueWatching = continueWatching
        self.favorites = favoriteMedia
        self.topRatedMovies = topRatedMovies
        self.topRatedSeries = topRatedSeries
        self.recentlyUpdated = recentlyUpdated
        self.recentlyAddedMediaIDs = recentlyAddedMediaIDs

        let heroSelection: (Media, HeroReason, WatchActivity?)? = if let entry = continueWatching.first {
            (entry.media, .continueWatching, entry.activity)
        } else if let item = favoriteMedia.first {
            (item, .favorite, nil)
        } else if let item = topRatedMovies.first {
            (item, .topRatedMovie, nil)
        } else if let item = topRatedSeries.first {
            (item, .topRatedSeries, nil)
        } else if let item = recentlyUpdated.first {
            (item, .recentlyUpdated, nil)
        } else {
            nil
        }

        if let (item, reason, activity) = heroSelection {
            let actions = Self.heroActions(
                for: item.type,
                isResumeEligible: activity?.isResumeEligible == true
            )
            self.hero = Hero(
                media: item,
                reason: reason,
                activity: activity,
                primaryAction: actions.primary,
                secondaryAction: actions.secondary
            )
            self.sparseState = nil
        } else {
            self.hero = nil
            self.sparseState = Self.makeSparseState(
                categories: categories,
                media: media,
                visibleMediaIDs: visibleMediaIDs,
                hiddenGroupKeys: hiddenGroupKeys,
                hydrationSnapshot: LibraryHydrationSnapshot(
                    categories: categories,
                    media: media,
                    overrides: runtimeHydrationStates
                ),
                syncStatus: syncStatus,
                syncErrorMessage: syncErrorMessage
            )
        }
    }

    func categoryTitle(for media: Media) -> String? {
        media.categoryID.flatMap { categoryByID[$0]?.title }
    }

    func isRecentlyAdded(_ media: Media) -> Bool {
        recentlyAddedMediaIDs.contains(media.id)
    }

    static func heroActions(
        for mediaType: MediaType,
        isResumeEligible: Bool
    ) -> (primary: HeroAction, secondary: HeroAction?) {
        switch mediaType {
        case .movie, .episode:
            return (
                isResumeEligible ? .resume : .play,
                .details
            )
        case .series:
            return (.browseEpisodes, nil)
        case .live:
            return (.details, nil)
        }
    }

    private static func makeSparseState(
        categories: [Category],
        media: [Media],
        visibleMediaIDs: Set<Media.ID>,
        hiddenGroupKeys: Set<String>,
        hydrationSnapshot: LibraryHydrationSnapshot,
        syncStatus: SyncManager.SyncStatus,
        syncErrorMessage: String?
    ) -> SparseState {
        var visibleCategories: [Category] = []
        visibleCategories.reserveCapacity(categories.count)
        for category in categories {
            let groupKey = CategoryGrouping.key(for: category.title)
            if !hiddenGroupKeys.contains(groupKey) {
                visibleCategories.append(category)
            }
        }

        let hydrationStates = visibleCategories.map {
            hydrationSnapshot.statesByCategoryID[$0.id] ?? .unhydrated
        }

        if syncStatus == .active || hydrationStates.contains(.loading) {
            return .loading
        }

        let hydrationFailure = hydrationStates.compactMap { state -> String? in
            guard case .failed(let message) = state else { return nil }
            return message
        }.first
        if syncStatus == .failure || hydrationFailure != nil {
            return .failed(syncErrorMessage ?? hydrationFailure)
        }

        let allCategoriesHidden = !categories.isEmpty
            && visibleCategories.isEmpty
            && !hiddenGroupKeys.isEmpty
        let allMediaHidden = !media.isEmpty
            && visibleMediaIDs.isEmpty
            && !hiddenGroupKeys.isEmpty
        if allCategoriesHidden || allMediaHidden {
            return .allHidden
        }

        if syncStatus == .success && categories.isEmpty && media.isEmpty {
            return .allEmpty
        }

        if hydrationStates.contains(.unhydrated)
            || (categories.isEmpty && media.isEmpty && syncStatus == .idle) {
            return .unhydrated
        }

        let allHydratedCategoriesEmpty = !hydrationStates.isEmpty
            && hydrationStates.allSatisfy { state in
                switch state {
                case .empty, .populated(0): true
                case .unhydrated, .loading, .populated, .failed: false
                }
            }
        if allHydratedCategoriesEmpty || (syncStatus == .success && media.isEmpty) {
            return .allEmpty
        }

        return .noRecommendations
    }

    private static func isDirectlyPlayable(_ media: Media) -> Bool {
        media.type == .movie || media.type == .episode
    }

    private static func ratingOrdered(_ lhs: Media, _ rhs: Media) -> Bool {
        LibraryFilterEngine.ordered(lhs, before: rhs, by: .rating)
    }

    private static func newestOrdered(_ lhs: Media, _ rhs: Media) -> Bool {
        LibraryFilterEngine.ordered(lhs, before: rhs, by: .newest)
    }

    private static func insertBounded<Element>(
        _ element: Element,
        into elements: inout [Element],
        orderedBefore: (Element, Element) -> Bool
    ) {
        let insertionIndex = elements.firstIndex { orderedBefore(element, $0) } ?? elements.endIndex
        guard insertionIndex < railLimit || elements.count < railLimit else { return }

        elements.insert(element, at: insertionIndex)
        if elements.count > railLimit {
            elements.removeLast()
        }
    }

}

struct ForYouScreen: View {
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(CategoryPrefixVisibilityStore.revisionKey) private var prefixVisibilityRevision = 0
    @AppStorage(FavoriteStore.revisionKey) private var favoritesRevision = 0

    @FetchAll(Category.where { $0.type.eq(MediaType.movie).or($0.type.eq(MediaType.series)).or($0.type.eq(MediaType.episode)) }) private var categories: [Category]
    @FetchAll(Media.where { $0.type.eq(MediaType.movie).or($0.type.eq(MediaType.series)).or($0.type.eq(MediaType.episode)) }) private var media: [Media]
    @FetchAll(WatchActivity.where { $0.completed.eq(false) }) private var watchActivities: [WatchActivity]
    @FetchAll private var favorites: [Favorite]

    @State private var selectedDetail: Media?
    @State private var prefixVisibilityCache = CategoryPrefixVisibilityCache()

    var body: some View {
        let visibilityRequest = CategoryPrefixVisibilityRequest(
            providerID: session.providerID,
            revision: prefixVisibilityRevision
        )

        NavigationStack {
            if let visibilitySnapshot = prefixVisibilityCache.snapshot(for: visibilityRequest) {
                content(
                    makeSnapshot(hiddenGroupKeys: visibilitySnapshot.hiddenGroupKeys)
                )
            } else {
                ProgressView("Loading library visibility…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("forYou.visibility.loading")
            }
        }
        .task(id: visibilityRequest) {
            prefixVisibilityCache.resolve(visibilityRequest) {
                CategoryPrefixVisibilityStore.snapshot(for: visibilityRequest)
            }
        }
    }

    private func content(_ snapshot: ForYouSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                if let hero = snapshot.hero {
                    ForYouHeroView(
                        hero: hero,
                        onAction: { perform($0, for: hero.media) }
                    )
                }

                if let sparseState = snapshot.sparseState {
                    emptyState(sparseState)
                } else {
                    rails(snapshot)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical)
        }
        .navigationTitle("For You")
        .navigationDestination(item: $selectedDetail) { item in
            MediaDetailDestination(
                media: item,
                categoryTitle: snapshot.categoryTitle(for: item)
            )
        }
    }

    private func makeSnapshot(hiddenGroupKeys: Set<String>) -> ForYouSnapshot {
        _ = favoritesRevision

        return ForYouSnapshot(
            providerID: session.providerID,
            categories: categories,
            media: media,
            watchActivities: watchActivities,
            favorites: favorites,
            hiddenGroupKeys: hiddenGroupKeys,
            runtimeHydrationStates: session.runtimeHydrationStates,
            syncStatus: session.sync,
            syncErrorMessage: session.syncErrorMessage
        )
    }

    @ViewBuilder
    private func rails(_ snapshot: ForYouSnapshot) -> some View {
        if !snapshot.continueWatching.isEmpty {
            ContinueWatchingRail(
                entries: snapshot.continueWatching,
                categoryTitle: snapshot.categoryTitle(for:)
            )
        }

        if !snapshot.favorites.isEmpty {
            ForYouRailView(
                title: "Favorites",
                subtitle: "Saved locally for this provider.",
                items: snapshot.favorites
            ) { item in
                MediaDetailDestination(
                    media: item,
                    categoryTitle: snapshot.categoryTitle(for: item)
                )
            }
        }

        if !snapshot.topRatedMovies.isEmpty {
            ForYouRailView(
                title: "Top Rated Movies",
                subtitle: "Highest rated movies in visible categories.",
                items: snapshot.topRatedMovies
            ) { item in
                MediaDetailDestination(
                    media: item,
                    categoryTitle: snapshot.categoryTitle(for: item)
                )
            }
        }

        if !snapshot.topRatedSeries.isEmpty {
            ForYouRailView(
                title: "Top Rated Series",
                subtitle: "Highest rated series in visible categories.",
                items: snapshot.topRatedSeries,
                badge: { _ in .series }
            ) { item in
                MediaDetailDestination(
                    media: item,
                    categoryTitle: snapshot.categoryTitle(for: item)
                )
            }
        }

        if !snapshot.recentlyUpdated.isEmpty {
            ForYouRailView(
                title: "Recently Updated",
                subtitle: "Newest movies and series in your visible catalog.",
                items: snapshot.recentlyUpdated,
                badge: { snapshot.isRecentlyAdded($0) ? .new : nil }
            ) { item in
                MediaDetailDestination(
                    media: item,
                    categoryTitle: snapshot.categoryTitle(for: item)
                )
            }
        }
    }

    private func emptyState(_ state: ForYouSnapshot.SparseState) -> some View {
        ContentUnavailableView {
            Label(emptyTitle(for: state), systemImage: emptySystemImage(for: state))
        } description: {
            Text(emptyDescription(for: state))
        } actions: {
            if state == .allHidden {
                Button("Clear Prefix Visibility") {
                    CategoryPrefixVisibilityStore.setHiddenGroupKeys([], for: session.providerID)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 420 : 320)
        .accessibilityElement(children: .contain)
    }

    private func emptyTitle(for state: ForYouSnapshot.SparseState) -> String {
        switch state {
        case .loading: "Loading your catalog"
        case .failed: "Catalog loading failed"
        case .unhydrated: "Catalog categories need loading"
        case .allEmpty: "The hydrated catalog is empty"
        case .allHidden: "All catalog groups are hidden"
        case .noRecommendations: "Nothing to recommend yet"
        }
    }

    private func emptySystemImage(for state: ForYouSnapshot.SparseState) -> String {
        switch state {
        case .loading: "clock.arrow.circlepath"
        case .failed: "exclamationmark.triangle"
        case .unhydrated: "folder.badge.questionmark"
        case .allEmpty: "tray"
        case .allHidden: "line.3.horizontal.decrease.circle"
        case .noRecommendations: "sparkles"
        }
    }

    private func emptyDescription(for state: ForYouSnapshot.SparseState) -> String {
        switch state {
        case .loading:
            "Recommendations will appear as local catalog rows finish loading."
        case .failed(let message):
            message ?? "The provider could not load catalog data. Retry the provider sync from Settings."
        case .unhydrated:
            "Open a Movies or Series category in Browse to load its streams into the local library."
        case .allEmpty:
            "The categories finished loading but did not contain any movies or series."
        case .allHidden:
            "Prefix visibility settings hide every local row available for discovery."
        case .noRecommendations:
            "Watch something, add a favorite, or load movie and series rows to populate this screen."
        }
    }

    private func perform(_ action: ForYouSnapshot.HeroAction, for media: Media) {
        switch action {
        case .resume, .play:
            guard media.type == .movie || media.type == .episode else {
                assertionFailure("For You produced a playback action for non-playable media.")
                return
            }
            player.load(media, presentation: .fullWindow)
        case .browseEpisodes, .details:
            selectedDetail = media
        }
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        56
        #elseif os(macOS)
        24
        #else
        horizontalSizeClass == .compact ? 16 : 24
        #endif
    }

    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        48
        #else
        dynamicTypeSize.isAccessibilitySize ? 36 : 28
        #endif
    }
}

private struct ContinueWatchingRail: View {
    let entries: [ForYouSnapshot.ContinueWatchingEntry]
    let categoryTitle: (Media) -> String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Continue Watching")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Your most recently watched movies and episodes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: cardSpacing) {
                    ForEach(entries) { entry in
                        NavigationLink {
                            MediaDetailDestination(
                                media: entry.media,
                                categoryTitle: categoryTitle(entry.media)
                            )
                        } label: {
                            ContinueWatchingCardView(
                                item: entry.media,
                                activity: entry.activity,
                                progressDescription: entry.progressDescription
                            )
                            .frame(width: cardWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, focusPadding)
                #if os(tvOS)
                .focusSection()
                #endif
            }
            .scrollIndicators(.never)
        }
    }

    private var cardWidth: CGFloat {
        #if os(tvOS)
        300
        #elseif os(macOS)
        dynamicTypeSize.isAccessibilitySize ? 250 : 210
        #else
        if dynamicTypeSize.isAccessibilitySize { return 240 }
        return horizontalSizeClass == .compact ? 180 : 210
        #endif
    }

    private var cardSpacing: CGFloat {
        #if os(tvOS)
        36
        #else
        16
        #endif
    }

    private var focusPadding: CGFloat {
        #if os(tvOS)
        18
        #else
        2
        #endif
    }
}

#Preview {
    ForYouScreen()
}
