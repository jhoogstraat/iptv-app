import Foundation
import Testing

@testable import iptv

@MainActor
@Suite("For You snapshot")
struct ForYouSnapshotTests {
    private let providerID = 42
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func heroFallbacksKeepTruthfulReasonsAndActions() throws {
        let movie = makeMedia(id: 1, sourceID: 101, type: .movie, title: "Movie", rating: 9)
        let series = makeMedia(id: 2, sourceID: 102, type: .series, title: "Series", rating: 8)
        let episode = makeMedia(id: 3, sourceID: 103, type: .episode, title: "Episode")
        let unratedMovie = makeMedia(id: 4, sourceID: 104, type: .movie, title: "Recent")

        let activity = makeActivity(id: 1, media: episode, currentTime: 90, duration: 900)
        let continueSnapshot = makeSnapshot(media: [movie, series, episode], activities: [activity])
        let continueHero = try #require(continueSnapshot.hero)
        #expect(continueHero.reason == .continueWatching)
        #expect(continueHero.media.sourceID == episode.sourceID)
        #expect(continueHero.primaryAction == .resume)
        #expect(continueHero.secondaryAction == .details)

        let favorite = makeFavorite(id: 1, media: series)
        let favoriteSnapshot = makeSnapshot(media: [movie, series], favorites: [favorite])
        let favoriteHero = try #require(favoriteSnapshot.hero)
        #expect(favoriteHero.reason == .favorite)
        #expect(favoriteHero.media.sourceID == series.sourceID)
        #expect(favoriteHero.primaryAction == .browseEpisodes)
        #expect(favoriteHero.secondaryAction == nil)

        let movieSnapshot = makeSnapshot(media: [movie, series])
        let movieHero = try #require(movieSnapshot.hero)
        #expect(movieHero.reason == .topRatedMovie)
        #expect(movieHero.media.sourceID == movie.sourceID)
        #expect(movieHero.primaryAction == .play)
        #expect(movieHero.secondaryAction == .details)

        let seriesSnapshot = makeSnapshot(media: [series])
        let seriesHero = try #require(seriesSnapshot.hero)
        #expect(seriesHero.reason == .topRatedSeries)
        #expect(seriesHero.primaryAction == .browseEpisodes)
        #expect(seriesHero.secondaryAction == nil)

        let recentSnapshot = makeSnapshot(media: [unratedMovie])
        let recentHero = try #require(recentSnapshot.hero)
        #expect(recentHero.reason == .recentlyUpdated)
        #expect(recentHero.primaryAction == .play)
        #expect(recentHero.secondaryAction == .details)
    }

    @Test func heroActionModelCoversEveryMediaTypeWithoutDuplicateSeriesRouting() {
        let movie = ForYouSnapshot.heroActions(for: .movie, isResumeEligible: true)
        #expect(movie.primary == .resume)
        #expect(movie.secondary == .details)

        let episode = ForYouSnapshot.heroActions(for: .episode, isResumeEligible: false)
        #expect(episode.primary == .play)
        #expect(episode.secondary == .details)

        let series = ForYouSnapshot.heroActions(for: .series, isResumeEligible: true)
        #expect(series.primary == .browseEpisodes)
        #expect(series.secondary == nil)
        #expect(series.primary != .play)
        #expect(series.primary != .resume)

        let live = ForYouSnapshot.heroActions(for: .live, isResumeEligible: false)
        #expect(live.primary == .details)
        #expect(live.secondary == nil)
    }

    @Test func sparseStatesDistinguishUnhydratedLoadingFailureAndHydratedEmpty() {
        let unhydratedCategory = makeCategory(id: 1, title: "Movies", updatedAt: nil)
        let hydratedCategory = makeCategory(id: 2, title: "Series", type: .series, updatedAt: now)

        let unhydrated = makeSnapshot(categories: [unhydratedCategory])
        #expect(unhydrated.sparseState == .unhydrated)

        let loading = makeSnapshot(
            categories: [unhydratedCategory],
            runtimeHydrationStates: [unhydratedCategory.id: .loading]
        )
        #expect(loading.sparseState == .loading)

        let failed = makeSnapshot(
            categories: [unhydratedCategory],
            runtimeHydrationStates: [unhydratedCategory.id: .failed("Network unavailable")]
        )
        #expect(failed.sparseState == .failed("Network unavailable"))

        let allEmpty = makeSnapshot(categories: [hydratedCategory])
        #expect(allEmpty.sparseState == .allEmpty)

        let initialLoading = makeSnapshot(syncStatus: .active)
        #expect(initialLoading.sparseState == .loading)

        let initialFailure = makeSnapshot(syncStatus: .failure, syncErrorMessage: "Provider failed")
        #expect(initialFailure.sparseState == .failed("Provider failed"))

        let successfulEmpty = makeSnapshot(syncStatus: .success)
        #expect(successfulEmpty.sparseState == .allEmpty)
    }

    @Test func nilDurationActivityKeepsSavedElapsedTimeAndResumeAction() throws {
        let movie = makeMedia(id: 1, sourceID: 101, type: .movie, title: "Unknown Duration")
        let activity = makeActivity(id: 1, media: movie, currentTime: 125, duration: nil)

        let snapshot = makeSnapshot(media: [movie], activities: [activity])
        let entry = try #require(snapshot.continueWatching.first)
        let hero = try #require(snapshot.hero)

        #expect(entry.progressDescription == "2m watched")
        #expect(hero.primaryAction == .resume)
        #expect(hero.activity?.currentTime == 125)
    }

    @Test func hiddenGroupsExcludeEveryRailAndProduceRecoverableSparseState() {
        let hiddenCategory = makeCategory(id: 7, title: "|NL| Movies", updatedAt: now)
        let hiddenMovie = makeMedia(
            id: 1,
            sourceID: 101,
            type: .movie,
            title: "Hidden",
            categoryID: hiddenCategory.id,
            rating: 9
        )
        let activity = makeActivity(id: 1, media: hiddenMovie, currentTime: 90, duration: 600)
        let favorite = makeFavorite(id: 1, media: hiddenMovie)

        let snapshot = makeSnapshot(
            categories: [hiddenCategory],
            media: [hiddenMovie],
            activities: [activity],
            favorites: [favorite],
            hiddenGroupKeys: ["NL"]
        )

        #expect(snapshot.continueWatching.isEmpty)
        #expect(snapshot.favorites.isEmpty)
        #expect(snapshot.topRatedMovies.isEmpty)
        #expect(snapshot.topRatedSeries.isEmpty)
        #expect(snapshot.recentlyUpdated.isEmpty)
        #expect(snapshot.hero == nil)
        #expect(snapshot.sparseState == .allHidden)
    }

    @Test func railsAreDeterministicAndCappedIndependentOfInputOrder() {
        let rows = (0..<30).map { index in
            makeMedia(
                id: index + 1,
                sourceID: 1_000 - index,
                type: .movie,
                title: "Same Title",
                rating: Double(index % 4),
                updatedAt: now
            )
        }

        let forward = makeSnapshot(media: rows)
        let reversed = makeSnapshot(media: Array(rows.reversed()))
        let expectedRatings = rows.sorted { lhs, rhs in
            if lhs.rating != rhs.rating {
                return lhs.rating! > rhs.rating!
            }
            return lhs.sourceID < rhs.sourceID
        }
        .prefix(ForYouSnapshot.railLimit)
        .map(\.sourceID)
        let expectedRecent = rows.sorted { $0.sourceID < $1.sourceID }
            .prefix(ForYouSnapshot.railLimit)
            .map(\.sourceID)

        #expect(forward.topRatedMovies.count == ForYouSnapshot.railLimit)
        #expect(forward.recentlyUpdated.count == ForYouSnapshot.railLimit)
        #expect(forward.topRatedMovies.map(\.sourceID) == expectedRatings)
        #expect(reversed.topRatedMovies.map(\.sourceID) == expectedRatings)
        #expect(forward.recentlyUpdated.map(\.sourceID) == expectedRecent)
        #expect(reversed.recentlyUpdated.map(\.sourceID) == expectedRecent)

        let sameMovie = makeMedia(id: 100, sourceID: 77, type: .movie, title: "Tie", updatedAt: now)
        let sameSeries = makeMedia(id: 101, sourceID: 77, type: .series, title: "Tie", updatedAt: now)
        let mixed = makeSnapshot(media: [sameSeries, sameMovie])
        #expect(mixed.recentlyUpdated.map(\.type) == [.movie, .series])
    }

    @Test func accessibilityIdentityDoesNotDependOnArtworkPhaseOrMutableMetadata() {
        let original = makeMedia(
            id: 1,
            sourceID: 900,
            type: .series,
            title: "Original",
            coverURL: URL(string: "https://example.com/one.jpg")
        )
        let refreshed = makeMedia(
            id: 2,
            sourceID: 900,
            type: .series,
            title: "Refreshed",
            coverURL: nil
        )

        #expect(ForYouMediaIdentity.poster(for: original) == ForYouMediaIdentity.poster(for: refreshed))
        #expect(ForYouMediaIdentity.continueWatching(for: original) == ForYouMediaIdentity.continueWatching(for: refreshed))
    }

    private func makeSnapshot(
        categories: [iptv.Category] = [],
        media: [Media] = [],
        activities: [WatchActivity] = [],
        favorites: [Favorite] = [],
        hiddenGroupKeys: Set<String> = [],
        runtimeHydrationStates: [iptv.Category.ID: SyncManager.CategoryHydrationState] = [:],
        syncStatus: SyncManager.SyncStatus = .idle,
        syncErrorMessage: String? = nil
    ) -> ForYouSnapshot {
        ForYouSnapshot(
            providerID: providerID,
            categories: categories,
            media: media,
            watchActivities: activities,
            favorites: favorites,
            hiddenGroupKeys: hiddenGroupKeys,
            runtimeHydrationStates: runtimeHydrationStates,
            syncStatus: syncStatus,
            syncErrorMessage: syncErrorMessage,
            now: now
        )
    }

    private func makeCategory(
        id: iptv.Category.ID,
        title: String,
        type: MediaType = .movie,
        updatedAt: Date?
    ) -> iptv.Category {
        iptv.Category(
            id: id,
            sourceID: "category-\(id)",
            type: type,
            title: title,
            updatedAt: updatedAt
        )
    }

    private func makeMedia(
        id: Media.ID,
        sourceID: Int,
        type: MediaType,
        title: String,
        categoryID: iptv.Category.ID? = nil,
        coverURL: URL? = nil,
        rating: Double? = nil,
        updatedAt: Date? = nil
    ) -> Media {
        Media(
            id: id,
            sourceID: sourceID,
            type: type,
            title: title,
            categoryID: categoryID,
            tmdbID: nil,
            coverURL: coverURL,
            rating: rating,
            updatedAt: updatedAt ?? now
        )
    }

    private func makeActivity(
        id: WatchActivity.ID,
        media: Media,
        currentTime: Double,
        duration: Double?
    ) -> WatchActivity {
        WatchActivity(
            id: id,
            profileID: UserProfileStore.primaryProfileID,
            providerID: providerID,
            mediaType: media.type,
            sourceID: media.sourceID,
            title: media.title,
            artworkURL: media.coverURL,
            categoryTitle: nil,
            currentTime: currentTime,
            duration: duration,
            completed: false,
            lastWatchedAt: now,
            updatedAt: now
        )
    }

    private func makeFavorite(id: Favorite.ID, media: Media) -> Favorite {
        Favorite(
            id: id,
            profileID: UserProfileStore.primaryProfileID,
            providerID: providerID,
            mediaType: media.type,
            sourceID: media.sourceID,
            title: media.title,
            artworkURL: media.coverURL,
            categoryID: media.categoryID,
            categoryTitle: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
