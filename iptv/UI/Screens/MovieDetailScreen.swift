//
//  MovieDetailScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 08.09.25.
//

import SwiftUI
import SQLiteData

struct MediaDetailDestination: View {
    let media: Media
    let categoryTitle: String?

    init(media: Media, categoryTitle: String? = nil) {
        self.media = media
        self.categoryTitle = categoryTitle
    }

    var body: some View {
        switch media.type {
        case .movie:
            MovieDetailScreen(movie: media, categoryTitle: categoryTitle)
        case .series:
            SeriesDetailScreen(series: media, categoryTitle: categoryTitle)
        case .episode:
            EpisodeDetailTile(series: nil, episode: media)
        case .live:
            ScopedPlaceholderView(
                title: "Live TV details unavailable",
                message: "Live channel details are not part of this local-data foundation workstream."
            )
        }
    }
}

struct MovieDetailScreen: View {
    @AppStorage(UserProfileStore.revisionKey) private var profileRevision = 0
    let movie: Media
    let categoryTitle: String?

    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FetchOne private var persistedMovie: Media?
    @FetchAll private var watchActivities: [WatchActivity]
    @FetchAll private var favorites: [Favorite]
    @State private var playError: String?
    @State private var favoriteError: String?
    @State private var enrichmentState = DetailEnrichmentState.idle
    @State private var enrichmentRequestID = 0
    @State private var heroCollapseProgress: CGFloat = 0
    @State private var heroScrollOffset: CGFloat = 0

    init(movie: Media, categoryTitle: String? = nil) {
        self.movie = movie
        self.categoryTitle = categoryTitle
        self._persistedMovie = FetchOne(Media.where { $0.id.eq(movie.id) })
        self._watchActivities = FetchAll(WatchActivity.where {
            $0.mediaType.eq(movie.type)
                .and($0.sourceID.eq(movie.sourceID))
        })
        self._favorites = FetchAll(Favorite.where {
            $0.mediaType.eq(movie.type)
                .and($0.sourceID.eq(movie.sourceID))
        })
    }

    private var currentMovie: Media { persistedMovie ?? movie }

    private var currentWatchActivity: WatchActivity? {
        watchActivities.first {
            $0.profileID == session.activeProfileID
                && $0.providerID == session.providerID
                && $0.mediaType == currentMovie.type
                && $0.sourceID == currentMovie.sourceID
        }
    }

    private var currentFavorite: Favorite? {
        favorites.first {
            $0.profileID == session.activeProfileID
                && $0.providerID == session.providerID
                && $0.mediaType == currentMovie.type
                && $0.sourceID == currentMovie.sourceID
        }
    }

    private var shouldResumeCurrentMovie: Bool {
        currentWatchActivity?.isResumeEligible == true
    }

    private var heroTitleAccessibilityHidden: Bool {
        #if os(iOS) || os(visionOS)
        DetailHeroCollapse.collapsedHeaderIsAccessible(progress: heroCollapseProgress)
        #else
        true
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 700
            let stackHeroContent = isCompact || dynamicTypeSize.isAccessibilitySize
            let topInset = proxy.safeAreaInsets.top
            let backdropHeight = min(max(proxy.size.height * 0.52, 360), 560)
            let collapseDistance = min(max(proxy.size.height * 0.2, 120), 220)

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(
                            availableWidth: proxy.size.width,
                            backdropHeight: backdropHeight,
                            topInset: topInset,
                            stackContent: stackHeroContent
                        )
                        .background {
                            heroScrollMetrics(collapseDistance: collapseDistance)
                        }

                        DetailContentLayout(isCompact: isCompact, availableWidth: proxy.size.width) {
                            section("Synopsis", text: synopsisText)
                            metadataSection
                            availabilitySection
                        }
                        .background(Color.black)
                    }
                }
                .coordinateSpace(name: DetailScrollCoordinateSpace.name)
                .onPreferenceChange(DetailHeroProgressPreferenceKey.self) {
                    heroCollapseProgress = $0
                }
                .onPreferenceChange(DetailHeroScrollOffsetPreferenceKey.self) {
                    heroScrollOffset = $0
                }
                .background(Color.black)

                platformTopControls(topInset: topInset)
            }
            .background(Color.black)
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle(currentMovie.title)
        .detailNavigationChrome()
        .task(id: enrichmentRequestID) {
            await enrichCurrentMovie()
        }
    }

    private func hero(
        availableWidth: CGFloat,
        backdropHeight: CGFloat,
        topInset: CGFloat,
        stackContent: Bool
    ) -> some View {
        let movie = currentMovie

        return ZStack(alignment: .topLeading) {
            DetailHeroBackdrop(
                artworkURL: movie.backdropURL ?? movie.coverURL,
                height: backdropHeight,
                topInset: topInset,
                collapseProgress: heroCollapseProgress,
                scrollOffset: heroScrollOffset,
                artworkContentMode: .fill
            )

            VStack(alignment: .leading, spacing: DetailSpacing.md) {
                Text(categoryTitle ?? "Movie")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))

                Text(movie.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHidden(heroTitleAccessibilityHidden)

                metadataPills(stacked: stackContent)

                Text(synopsisText)
                    .font(.callout)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: 680, alignment: .leading)

                actionRow(stacked: stackContent)

                if let playError {
                    Text(playError)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red.opacity(0.94))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel("Playback error: \(playError)")
                }
            }
            .padding(.top, topInset + max(132, backdropHeight * 0.28))
            .padding(.horizontal, availableWidth < 700 ? 20 : 40)
            .padding(.bottom, DetailSpacing.xl)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: backdropHeight + topInset, alignment: .topLeading)
        .background(Color.black)
    }

    private func metadataPills(stacked: Bool) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DetailSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DetailSpacing.xs))

        return layout {
            DetailMetaPill(label: "Media type", value: "Movie", systemImage: "film")

            if let year = releaseYear {
                DetailMetaPill(label: "Release year", value: year, systemImage: "calendar")
            }

            if let runtime = formattedRuntime {
                DetailMetaPill(label: "Runtime", value: runtime, systemImage: "clock")
            }

            if let rating = currentMovie.rating {
                DetailMetaPill(
                    label: "Rating",
                    value: rating.formatted(.number.precision(.fractionLength(1))),
                    systemImage: "star.fill"
                )
            }
        }
    }

    private func actionRow(stacked: Bool) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DetailSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DetailSpacing.sm))

        return VStack(alignment: .leading, spacing: DetailSpacing.xs) {
            layout {
                Button {
                    playError = nil
                    player.load(currentMovie, presentation: .fullWindow)
                    playError = player.errorMessage
                } label: {
                    Label(
                        playButtonTitle,
                        systemImage: shouldResumeCurrentMovie ? "play.circle.fill" : "play.fill"
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DetailActionStyle(variant: .primary))

                Button(action: toggleFavorite) {
                    Label(
                        currentFavorite == nil ? "Add to Favorites" : "Remove from Favorites",
                        systemImage: currentFavorite == nil ? "heart" : "heart.fill"
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DetailActionStyle(variant: .secondary))
                .accessibilityHint("Updates the persisted favorite state for this provider.")

                DownloadStatusBadge(presentation: .detailAction(.secondary))
                    .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
            }
            .frame(maxWidth: 720, alignment: .leading)

            if let favoriteError {
                Text(favoriteError)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Favorite error: \(favoriteError)")
                    .frame(maxWidth: 720, alignment: .leading)
            }

            resumeSummary
                .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var playButtonTitle: String {
        guard shouldResumeCurrentMovie, let activity = currentWatchActivity else { return "Play" }
        return "Resume \(Self.formatDuration(activity.currentTime))"
    }

    @ViewBuilder
    private var resumeSummary: some View {
        if let activity = currentWatchActivity, activity.isResumeEligible {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: activity.progressFraction)
                    .tint(.white)

                Text(resumeSummaryText(for: activity))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(resumeSummaryText(for: activity))
        } else if currentWatchActivity?.completed == true {
            Text("Watched. Play starts from the beginning.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.sm) {
            DetailSectionHeader(title: "Library Metadata")
            DetailMetadataGrid(rows: metadataRows)
        }
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.sm) {
            DetailSectionHeader(title: "Source and Downloads")
            Text("Playback uses the active provider’s saved source. Favorites are stored for this provider. Offline downloads are unavailable.")
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DetailEnrichmentStatus(state: enrichmentState, retry: retryEnrichment)
        }
    }

    private var metadataRows: [DetailMetadataRow] {
        let movie = currentMovie

        return [
            DetailMetadataRow(label: "Type", value: "Movie"),
            DetailMetadataRow(label: "Category", value: categoryTitle),
            DetailMetadataRow(label: "Rating", value: movie.rating.map { $0.formatted(.number.precision(.fractionLength(1))) }),
            DetailMetadataRow(label: "Release", value: movie.releaseDate?.formatted(date: .abbreviated, time: .omitted)),
            DetailMetadataRow(label: "Runtime", value: formattedRuntime),
            DetailMetadataRow(label: "Genre", value: movie.genre),
            DetailMetadataRow(label: "Cast", value: movie.cast),
            DetailMetadataRow(label: "Director", value: movie.director),
            DetailMetadataRow(label: "Country", value: movie.country),
            DetailMetadataRow(label: "Trailer", value: movie.trailer),
            DetailMetadataRow(label: "Added", value: movie.addedAt?.formatted(date: .abbreviated, time: .shortened)),
            DetailMetadataRow(label: "TMDB", value: movie.tmdbID),
            DetailMetadataRow(label: "Source ID", value: String(movie.sourceID)),
            DetailMetadataRow(label: "Updated", value: movie.updatedAt.formatted(date: .abbreviated, time: .shortened))
        ]
    }

    private var synopsisText: String {
        unavailableAwareText(
            currentMovie.synopsis,
            fallback: "No synopsis is available in the synced library record."
        )
    }

    private var releaseYear: String? {
        currentMovie.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }
    }

    private var formattedRuntime: String? {
        guard let runtimeSeconds = currentMovie.runtimeSeconds, runtimeSeconds > 0 else { return nil }
        let hours = runtimeSeconds / 3600
        let minutes = (runtimeSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func unavailableAwareText(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        return value
    }

    private func toggleFavorite() {
        do {
            _ = try FavoriteStore.toggle(
                currentMovie,
                providerID: session.providerID,
                categoryTitle: categoryTitle
            )
            favoriteError = nil
        } catch {
            favoriteError = error.localizedDescription
        }
    }

    private func enrichCurrentMovie() async {
        if enrichmentState == .idle {
            enrichmentState.transition(.request)
        }
        guard enrichmentState == .loading else { return }

        do {
            try await session.enrichDetails(for: currentMovie)
            enrichmentState.transition(.succeeded)
        } catch is CancellationError {
            enrichmentState.transition(.cancelled)
        } catch {
            enrichmentState.transition(.failed(error.localizedDescription))
        }
    }

    private func retryEnrichment() {
        enrichmentState.transition(.retry)
        guard enrichmentState == .loading else { return }
        enrichmentRequestID &+= 1
    }

    private func resumeSummaryText(for activity: WatchActivity) -> String {
        if let remaining = activity.remainingSeconds {
            return "\(Self.formatDuration(activity.currentTime)) watched • \(Self.formatDuration(remaining)) left"
        }

        return "\(Self.formatDuration(activity.currentTime)) watched"
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DetailSpacing.xs) {
            DetailSectionHeader(title: title)
            Text(text)
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func heroScrollMetrics(collapseDistance: CGFloat) -> some View {
        GeometryReader { heroProxy in
            let minY = heroProxy.frame(in: .named(DetailScrollCoordinateSpace.name)).minY

            Color.clear
                .preference(
                    key: DetailHeroProgressPreferenceKey.self,
                    value: DetailHeroCollapse.progress(
                        heroMinY: minY,
                        collapseDistance: collapseDistance
                    )
                )
                .preference(key: DetailHeroScrollOffsetPreferenceKey.self, value: minY)
        }
    }

    @ViewBuilder
    private func platformTopControls(topInset: CGFloat) -> some View {
        #if os(iOS) || os(visionOS)
        topControls(topInset: topInset)
        #else
        EmptyView()
        #endif
    }

    private func topControls(topInset: CGFloat) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(DetailActionStyle(variant: .icon))
            .accessibilityLabel("Back")

            Spacer()

            DetailCollapsedHeaderBar(
                title: currentMovie.title,
                artworkURL: currentMovie.coverURL,
                titleArtworkURL: nil,
                progress: heroCollapseProgress
            )
        }
        .padding(.top, topInset + 10)
        .padding(.horizontal, 16)
    }
}

struct SeriesDetailScreen: View {
    @AppStorage(UserProfileStore.revisionKey) private var profileRevision = 0
    private enum DetailTab: String, CaseIterable, Identifiable {
        case episodes = "Episodes"
        case details = "Details"

        var id: String { rawValue }
    }

    static let episodePlaybackPresentation: Presentation = .fullWindow

    let series: Media
    let categoryTitle: String?

    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FetchOne private var persistedSeries: Media?
    @FetchAll private var seasons: [SeriesSeason]
    @FetchAll private var episodes: [Media]
    @FetchAll private var favorites: [Favorite]
    @State private var selectedTab: DetailTab = .episodes
    @State private var selectedSeasonNumber: Int?
    @State private var favoriteError: String?
    @State private var episodePlaybackError: String?
    @State private var enrichmentState = DetailEnrichmentState.idle
    @State private var enrichmentRequestID = 0
    @State private var heroCollapseProgress: CGFloat = 0
    @State private var heroScrollOffset: CGFloat = 0

    init(series: Media, categoryTitle: String? = nil) {
        self.series = series
        self.categoryTitle = categoryTitle
        self._persistedSeries = FetchOne(Media.where { $0.id.eq(series.id) })
        self._seasons = FetchAll(SeriesSeason.where { $0.seriesID.eq(series.id) })
        self._episodes = FetchAll(Media.where {
            $0.type.eq(MediaType.episode)
                .and($0.parentSeriesID.eq(series.id))
        })
        self._favorites = FetchAll(Favorite.where {
            $0.mediaType.eq(series.type)
                .and($0.sourceID.eq(series.sourceID))
        })
    }

    private var currentSeries: Media { persistedSeries ?? series }

    private var currentFavorite: Favorite? {
        favorites.first {
            $0.profileID == session.activeProfileID
                && $0.providerID == session.providerID
                && $0.mediaType == currentSeries.type
                && $0.sourceID == currentSeries.sourceID
        }
    }

    private var heroTitleAccessibilityHidden: Bool {
        #if os(iOS) || os(visionOS)
        DetailHeroCollapse.collapsedHeaderIsAccessible(progress: heroCollapseProgress)
        #else
        true
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 700
            let stackHeroContent = isCompact || dynamicTypeSize.isAccessibilitySize
            let topInset = proxy.safeAreaInsets.top
            let backdropHeight = min(max(proxy.size.height * 0.5, 350), 540)
            let collapseDistance = min(max(proxy.size.height * 0.2, 120), 220)

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(
                            availableWidth: proxy.size.width,
                            backdropHeight: backdropHeight,
                            topInset: topInset,
                            stackContent: stackHeroContent
                        )
                        .background {
                            heroScrollMetrics(collapseDistance: collapseDistance)
                        }

                        DetailContentLayout(isCompact: isCompact, availableWidth: proxy.size.width) {
                            DetailEnrichmentStatus(state: enrichmentState, retry: retryEnrichment)

                            Picker("Series detail section", selection: $selectedTab) {
                                ForEach(DetailTab.allCases) { tab in
                                    Text(tab.rawValue).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)

                            switch selectedTab {
                            case .episodes:
                                episodesSection
                            case .details:
                                detailsSection
                            }
                        }
                        .background(Color.black)
                    }
                }
                .coordinateSpace(name: DetailScrollCoordinateSpace.name)
                .onPreferenceChange(DetailHeroProgressPreferenceKey.self) {
                    heroCollapseProgress = $0
                }
                .onPreferenceChange(DetailHeroScrollOffsetPreferenceKey.self) {
                    heroScrollOffset = $0
                }
                .background(Color.black)

                platformTopControls(topInset: topInset)
            }
            .background(Color.black)
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle(currentSeries.title)
        .detailNavigationChrome()
        .task(id: enrichmentRequestID) {
            await enrichCurrentSeries()
        }
        .onAppear(perform: synchronizeSelectedSeason)
        .onChange(of: seasonNumbers) { _, _ in
            synchronizeSelectedSeason()
        }
    }

    private func hero(
        availableWidth: CGFloat,
        backdropHeight: CGFloat,
        topInset: CGFloat,
        stackContent: Bool
    ) -> some View {
        let series = currentSeries

        return ZStack(alignment: .topLeading) {
            DetailHeroBackdrop(
                artworkURL: series.backdropURL ?? series.coverURL,
                height: backdropHeight,
                topInset: topInset,
                collapseProgress: heroCollapseProgress,
                scrollOffset: heroScrollOffset,
                artworkContentMode: .fill
            )

            VStack(alignment: .leading, spacing: DetailSpacing.md) {
                Text(categoryTitle ?? "Series")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))

                Text(series.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHidden(heroTitleAccessibilityHidden)

                metadataPills(stacked: stackContent)

                Text(synopsisText)
                    .font(.callout)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: 680, alignment: .leading)

                actionRow(stacked: stackContent)
            }
            .padding(.top, topInset + max(128, backdropHeight * 0.28))
            .padding(.horizontal, availableWidth < 700 ? 20 : 40)
            .padding(.bottom, DetailSpacing.xl)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: backdropHeight + topInset, alignment: .topLeading)
        .background(Color.black)
    }

    private func metadataPills(stacked: Bool) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DetailSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DetailSpacing.xs))

        return layout {
            DetailMetaPill(label: "Media type", value: "Series", systemImage: "tv")

            if let year = releaseYear {
                DetailMetaPill(label: "Release year", value: year, systemImage: "calendar")
            }

            if let rating = currentSeries.rating {
                DetailMetaPill(
                    label: "Rating",
                    value: rating.formatted(.number.precision(.fractionLength(1))),
                    systemImage: "star.fill"
                )
            }

            DetailMetaPill(label: "Episode count", value: episodeCountTitle, systemImage: "rectangle.stack")
        }
    }

    private func actionRow(stacked: Bool) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DetailSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DetailSpacing.sm))

        return VStack(alignment: .leading, spacing: DetailSpacing.xs) {
            layout {
                Button {
                    selectedTab = .episodes
                } label: {
                    Label(
                        episodes.isEmpty ? "Episodes unavailable" : "Select Episode",
                        systemImage: "list.bullet.rectangle"
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DetailActionStyle(variant: .primary))
                .disabled(episodes.isEmpty)

                Button(action: toggleFavorite) {
                    Label(
                        currentFavorite == nil ? "Add to Favorites" : "Remove from Favorites",
                        systemImage: currentFavorite == nil ? "heart" : "heart.fill"
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DetailActionStyle(variant: .secondary))
                .accessibilityHint("Updates the persisted favorite state for this provider.")

                DownloadStatusBadge(presentation: .detailAction(.secondary))
                    .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
            }
            .frame(maxWidth: 720, alignment: .leading)

            if let favoriteError {
                Text(favoriteError)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Favorite error: \(favoriteError)")
                    .frame(maxWidth: 720, alignment: .leading)
            }

            if let episodePlaybackError {
                Text(episodePlaybackError)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Playback error: \(episodePlaybackError)")
                    .frame(maxWidth: 720, alignment: .leading)
            }
        }
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.md) {
            HStack {
                DetailSectionHeader(title: "Episodes")
                Spacer()
                seasonMenu
            }

            if filteredEpisodes.isEmpty {
                ContentUnavailableView {
                    Label("Episodes unavailable", systemImage: "rectangle.stack.badge.person.crop")
                } description: {
                    Text(episodesUnavailableDescription)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVStack(spacing: DetailSpacing.sm) {
                    ForEach(filteredEpisodes) { episode in
                        Button {
                            episodePlaybackError = nil
                            player.load(episode, presentation: Self.episodePlaybackPresentation)
                            episodePlaybackError = player.errorMessage
                        } label: {
                            SeriesEpisodeRow(episode: episode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var seasonMenu: some View {
        if seasonNumbers.isEmpty {
            Menu("Season") {
                Button("Season data unavailable") {}
                    .disabled(true)
            }
            .buttonStyle(DetailActionStyle(variant: .chip(selected: false)))
            .disabled(true)
        } else {
            Menu(selectedSeasonTitle) {
                Button("All Seasons") {
                    selectedSeasonNumber = nil
                }

                ForEach(seasonNumbers, id: \.self) { number in
                    Button(seasonTitle(for: number)) {
                        selectedSeasonNumber = number
                    }
                }
            }
            .buttonStyle(DetailActionStyle(variant: .chip(selected: selectedSeasonNumber != nil)))
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.lg) {
            VStack(alignment: .leading, spacing: DetailSpacing.xs) {
                DetailSectionHeader(title: "Synopsis")
                Text(synopsisText)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: DetailSpacing.sm) {
                DetailSectionHeader(title: "Library Metadata")
                DetailMetadataGrid(rows: metadataRows)
            }
        }
    }

    private var metadataRows: [DetailMetadataRow] {
        let series = currentSeries

        return [
            DetailMetadataRow(label: "Type", value: "Series"),
            DetailMetadataRow(label: "Category", value: categoryTitle),
            DetailMetadataRow(label: "Rating", value: series.rating.map { $0.formatted(.number.precision(.fractionLength(1))) }),
            DetailMetadataRow(label: "Release", value: series.releaseDate?.formatted(date: .abbreviated, time: .omitted)),
            DetailMetadataRow(label: "Episode Run", value: formattedRuntime),
            DetailMetadataRow(label: "Genre", value: series.genre),
            DetailMetadataRow(label: "Cast", value: series.cast),
            DetailMetadataRow(label: "Director", value: series.director),
            DetailMetadataRow(label: "Trailer", value: series.trailer),
            DetailMetadataRow(label: "Episodes", value: episodes.isEmpty ? nil : String(episodes.count)),
            DetailMetadataRow(label: "TMDB", value: series.tmdbID),
            DetailMetadataRow(label: "Source ID", value: String(series.sourceID)),
            DetailMetadataRow(label: "Updated", value: series.updatedAt.formatted(date: .abbreviated, time: .shortened))
        ]
    }

    private var sortedEpisodes: [Media] {
        episodes.sorted { lhs, rhs in
            switch (lhs.seasonNumber, rhs.seasonNumber) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                break
            }

            switch (lhs.episodeNumber, rhs.episodeNumber) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private var filteredEpisodes: [Media] {
        guard let selectedSeasonNumber else { return sortedEpisodes }
        return sortedEpisodes.filter { $0.seasonNumber == selectedSeasonNumber }
    }

    private var seasonNumbers: [Int] {
        Array(Set(seasons.map(\.seasonNumber) + episodes.compactMap(\.seasonNumber))).sorted()
    }

    private var selectedSeasonTitle: String {
        selectedSeasonNumber.map(seasonTitle(for:)) ?? "All Seasons"
    }

    private var episodeCountTitle: String {
        episodes.isEmpty ? "Episodes unavailable" : "\(episodes.count) Episodes"
    }

    private var episodesUnavailableDescription: String {
        switch enrichmentState {
        case .idle:
            return "No saved episode rows are available yet."
        case .loading:
            return "Saved series information remains visible while episode details refresh."
        case .success:
            return "The provider returned no episode rows for this series."
        case .failure:
            return "Episode details could not be refreshed. Retry without leaving this screen."
        }
    }

    private var synopsisText: String {
        unavailableAwareText(
            currentSeries.synopsis,
            fallback: "No series synopsis is available in the synced library record."
        )
    }

    private var releaseYear: String? {
        currentSeries.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }
    }

    private var formattedRuntime: String? {
        guard let runtimeSeconds = currentSeries.runtimeSeconds, runtimeSeconds > 0 else { return nil }
        let minutes = runtimeSeconds / 60
        return "\(minutes)m"
    }

    private func seasonTitle(for number: Int) -> String {
        seasons.first { $0.seasonNumber == number }?.title ?? "Season \(number)"
    }

    private func unavailableAwareText(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        return value
    }

    private func synchronizeSelectedSeason() {
        if let selectedSeasonNumber, !seasonNumbers.contains(selectedSeasonNumber) {
            self.selectedSeasonNumber = nil
        }
    }

    private func toggleFavorite() {
        do {
            _ = try FavoriteStore.toggle(
                currentSeries,
                providerID: session.providerID,
                categoryTitle: categoryTitle
            )
            favoriteError = nil
        } catch {
            favoriteError = error.localizedDescription
        }
    }

    private func enrichCurrentSeries() async {
        if enrichmentState == .idle {
            enrichmentState.transition(.request)
        }
        guard enrichmentState == .loading else { return }

        do {
            try await session.enrichDetails(for: currentSeries)
            enrichmentState.transition(.succeeded)
            synchronizeSelectedSeason()
        } catch is CancellationError {
            enrichmentState.transition(.cancelled)
        } catch {
            enrichmentState.transition(.failed(error.localizedDescription))
        }
    }

    private func retryEnrichment() {
        enrichmentState.transition(.retry)
        guard enrichmentState == .loading else { return }
        enrichmentRequestID &+= 1
    }

    private func heroScrollMetrics(collapseDistance: CGFloat) -> some View {
        GeometryReader { heroProxy in
            let minY = heroProxy.frame(in: .named(DetailScrollCoordinateSpace.name)).minY

            Color.clear
                .preference(
                    key: DetailHeroProgressPreferenceKey.self,
                    value: DetailHeroCollapse.progress(
                        heroMinY: minY,
                        collapseDistance: collapseDistance
                    )
                )
                .preference(key: DetailHeroScrollOffsetPreferenceKey.self, value: minY)
        }
    }

    @ViewBuilder
    private func platformTopControls(topInset: CGFloat) -> some View {
        #if os(iOS) || os(visionOS)
        topControls(topInset: topInset)
        #else
        EmptyView()
        #endif
    }

    private func topControls(topInset: CGFloat) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(DetailActionStyle(variant: .icon))
            .accessibilityLabel("Back")

            Spacer()

            DetailCollapsedHeaderBar(
                title: currentSeries.title,
                artworkURL: currentSeries.coverURL,
                titleArtworkURL: nil,
                progress: heroCollapseProgress
            )
        }
        .padding(.top, topInset + 10)
        .padding(.horizontal, 16)
    }
}

private struct SeriesEpisodeRow: View {
    let episode: Media

    var body: some View {
        HStack(alignment: .top, spacing: DetailSpacing.md) {
            AsyncImage(url: episode.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .boundedFillArtwork()
                case .failure, .empty:
                    placeholderArtwork
                @unknown default:
                    placeholderArtwork
                }
            }
            .frame(width: 128, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: DetailSpacing.xs) {
                Text(episodeCode)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(episode.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(episodeSynopsis)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: DetailSpacing.sm) {
                    if let releaseDate = episode.releaseDate {
                        Label(releaseDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                    if let runtime = formattedRuntime {
                        Label(runtime, systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(DetailSpacing.sm)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var placeholderArtwork: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .overlay {
                Image(systemName: "play.rectangle")
                    .foregroundStyle(.secondary)
            }
    }

    private var episodeSynopsis: String {
        guard let synopsis = episode.synopsis?.trimmingCharacters(in: .whitespacesAndNewlines), !synopsis.isEmpty else {
            return "No episode synopsis is available in the synced library record."
        }
        return synopsis
    }

    private var episodeCode: String {
        switch (episode.seasonNumber, episode.episodeNumber) {
        case let (season?, episode?):
            return "S\(season) E\(episode)"
        case let (season?, nil):
            return "Season \(season)"
        case let (nil, episode?):
            return "Episode \(episode)"
        default:
            return "Episode"
        }
    }

    private var formattedRuntime: String? {
        guard let runtimeSeconds = episode.runtimeSeconds, runtimeSeconds > 0 else { return nil }
        return "\(runtimeSeconds / 60)m"
    }
}

struct DetailMetadataRow: Identifiable {
    let label: String
    let value: String?

    var id: String { label }
}

private struct DetailMetadataGrid: View {
    let rows: [DetailMetadataRow]

    var body: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.sm) {
            ForEach(rows) { row in
                metadataUnit(row)
            }
        }
        .padding(DetailSpacing.md)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func metadataUnit(_ row: DetailMetadataRow) -> some View {
        let value = displayValue(for: row)
        let isMissing = isMissing(row)

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DetailSpacing.md) {
                metadataLabel(row.label)
                    .frame(width: 96, alignment: .leading)

                selectableMetadataText(value, isMissing: isMissing)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: DetailSpacing.xxs) {
                metadataLabel(row.label)

                selectableMetadataText(value, isMissing: isMissing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.label)
        .accessibilityValue(value)
    }

    private func metadataLabel(_ label: String) -> some View {
        Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func selectableMetadataText(_ value: String, isMissing: Bool) -> some View {
        let text = Text(value)
            .font(.body)
            .foregroundStyle(isMissing ? .tertiary : .primary)

        #if os(tvOS)
        text
        #else
        text.textSelection(.enabled)
        #endif
    }

    private func isMissing(_ row: DetailMetadataRow) -> Bool {
        row.value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private func displayValue(for row: DetailMetadataRow) -> String {
        guard let value = row.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "Not available"
        }
        return value
    }
}

private extension View {
    @ViewBuilder
    func detailNavigationChrome() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        #elseif os(visionOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

#Preview {
    NavigationStack {
        Text("Movie detail preview requires synced media.")
    }
    .frame(width: 390, height: 844)
}
