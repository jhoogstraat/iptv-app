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
    let movie: Media
    let categoryTitle: String?

    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @FetchOne private var persistedMovie: Media?
    @FetchAll private var watchActivities: [WatchActivity]
    @State private var playError: String?
    @State private var enrichmentError: String?

    init(movie: Media, categoryTitle: String? = nil) {
        self.movie = movie
        self.categoryTitle = categoryTitle
        self._persistedMovie = FetchOne(Media.where { $0.id.eq(movie.id) })
        self._watchActivities = FetchAll(WatchActivity.where {
            $0.mediaType.eq(movie.type)
                .and($0.sourceID.eq(movie.sourceID))
        })
    }

    private var currentMovie: Media { persistedMovie ?? movie }

    private var currentWatchActivity: WatchActivity? {
        watchActivities.first {
            $0.providerID == session.providerID
                && $0.mediaType == currentMovie.type
                && $0.sourceID == currentMovie.sourceID
        }
    }

    private var shouldResumeCurrentMovie: Bool {
        currentWatchActivity?.isResumeEligible == true
    }


    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 700
            let topInset = proxy.safeAreaInsets.top
            let heroHeight = min(max(proxy.size.height * 0.58, 430), 590)

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(availableWidth: proxy.size.width, height: heroHeight, topInset: topInset)

                        DetailContentLayout(isCompact: isCompact, availableWidth: proxy.size.width) {
                            section("Synopsis", text: synopsisText)
                            metadataSection
                            availabilitySection
                        }
                        .background(Color.black)
                    }
                }
                .background(Color.black)

                topControls(topInset: topInset)
            }
            .background(Color.black)
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle(currentMovie.title)
        .detailNavigationChrome()
        .task(id: currentMovie.id) {
            await enrichCurrentMovie()
        }
    }

    private func hero(availableWidth: CGFloat, height: CGFloat, topInset: CGFloat) -> some View {
        let movie = currentMovie

        return ZStack(alignment: .bottomLeading) {
            DetailHeroBackdrop(
                artworkURL: movie.backdropURL ?? movie.coverURL,
                height: height,
                topInset: topInset,
                collapseProgress: 0,
                scrollOffset: 0,
                artworkContentMode: .fill
            )

            VStack(alignment: .leading, spacing: DetailSpacing.md) {
                Text(categoryTitle ?? "Movie")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))

                Text(movie.title)
                    .font(.system(size: availableWidth < 420 ? 42 : 58, weight: .black, design: .rounded))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)

                metadataPills

                Text(synopsisText)
                    .font(.callout)
                    .lineSpacing(4)
                    .lineLimit(3)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: 680, alignment: .leading)

                actionRow

                if let playError {
                    Text(playError)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red.opacity(0.94))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.55), in: Capsule(style: .continuous))
                        .accessibilityLabel("Playback error: \(playError)")
                }
            }
            .padding(.horizontal, availableWidth < 700 ? 20 : 40)
            .padding(.bottom, DetailSpacing.xl)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .frame(height: height + topInset)
    }

    private var metadataPills: some View {
        HStack(spacing: DetailSpacing.xs) {
            DetailMetaPill("Movie", systemImage: "film")

            if let year = releaseYear {
                DetailMetaPill(year, systemImage: "calendar")
            }

            if let runtime = formattedRuntime {
                DetailMetaPill(runtime, systemImage: "clock")
            }

            if let rating = currentMovie.rating {
                DetailMetaPill(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
            }
        }
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.xs) {
            HStack(spacing: DetailSpacing.sm) {
                Button {
                    playError = nil
                    player.load(currentMovie, presentation: .fullWindow)
                    playError = player.errorMessage
                } label: {
                    Label(playButtonTitle, systemImage: shouldResumeCurrentMovie ? "play.circle.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DetailActionStyle(variant: .primary))

                Button {} label: {
                    Label("Favorite unavailable", systemImage: "heart")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(DetailActionStyle(variant: .icon))
                .disabled(true)
                .accessibilityHint("Persistent favorites are outside the active Library UX workstream.")

                Button {} label: {
                    Label("Download unavailable", systemImage: "arrow.down.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(DetailActionStyle(variant: .icon))
                .disabled(true)
                .accessibilityHint("Downloads are outside the active Library UX workstream.")
            }
            .frame(maxWidth: 620)

            resumeSummary
                .frame(maxWidth: 620, alignment: .leading)
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
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(resumeSummaryText(for: activity))
        } else if currentWatchActivity?.completed == true {
            Text("Watched. Play starts from the beginning.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
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
            Text("Playback resolves from the active Xtream provider using the synced source identifier. Favorites and downloads are not persisted in this workstream.")
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.secondary)

            if let enrichmentError {
                Text("Detail metadata could not be refreshed: \(enrichmentError)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
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

    private func enrichCurrentMovie() async {
        do {
            try await session.enrichDetails(for: currentMovie)
            enrichmentError = nil
        } catch is CancellationError {
            return
        } catch {
            enrichmentError = error.localizedDescription
        }
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
        }
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
                progress: 1
            )
        }
        .padding(.top, topInset + 10)
        .padding(.horizontal, 16)
    }
}

struct SeriesDetailScreen: View {
    private enum DetailTab: String, CaseIterable, Identifiable {
        case episodes = "Episodes"
        case details = "Details"

        var id: String { rawValue }
    }

    let series: Media
    let categoryTitle: String?

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @FetchOne private var persistedSeries: Media?
    @FetchAll private var seasons: [SeriesSeason]
    @FetchAll private var episodes: [Media]
    @State private var selectedTab: DetailTab = .episodes
    @State private var selectedSeasonNumber: Int?
    @State private var enrichmentError: String?

    init(series: Media, categoryTitle: String? = nil) {
        self.series = series
        self.categoryTitle = categoryTitle
        self._persistedSeries = FetchOne(Media.where { $0.id.eq(series.id) })
        self._seasons = FetchAll(SeriesSeason.where { $0.seriesID.eq(series.id) })
        self._episodes = FetchAll(Media.where {
            $0.type.eq(MediaType.episode)
                .and($0.parentSeriesID.eq(series.id))
        })
    }

    private var currentSeries: Media { persistedSeries ?? series }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 700
            let topInset = proxy.safeAreaInsets.top
            let heroHeight = min(max(proxy.size.height * 0.54, 400), 560)

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(availableWidth: proxy.size.width, height: heroHeight, topInset: topInset)

                        DetailContentLayout(isCompact: isCompact, availableWidth: proxy.size.width) {
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
                .background(Color.black)

                topControls(topInset: topInset)
            }
            .background(Color.black)
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle(currentSeries.title)
        .detailNavigationChrome()
        .task(id: currentSeries.id) {
            await enrichCurrentSeries()
        }
        .onAppear(perform: synchronizeSelectedSeason)
        .onChange(of: seasonNumbers) { _, _ in
            synchronizeSelectedSeason()
        }
    }

    private func hero(availableWidth: CGFloat, height: CGFloat, topInset: CGFloat) -> some View {
        let series = currentSeries

        return ZStack(alignment: .bottomLeading) {
            DetailHeroBackdrop(
                artworkURL: series.backdropURL ?? series.coverURL,
                height: height,
                topInset: topInset,
                collapseProgress: 0,
                scrollOffset: 0,
                artworkContentMode: .fill
            )

            VStack(alignment: .leading, spacing: DetailSpacing.md) {
                Text(categoryTitle ?? "Series")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))

                Text(series.title)
                    .font(.system(size: availableWidth < 420 ? 40 : 56, weight: .black, design: .rounded))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)

                HStack(spacing: DetailSpacing.xs) {
                    DetailMetaPill("Series", systemImage: "tv")
                    if let year = releaseYear {
                        DetailMetaPill(year, systemImage: "calendar")
                    }
                    if let rating = series.rating {
                        DetailMetaPill(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                    }
                    DetailMetaPill(episodeCountTitle, systemImage: "rectangle.stack")
                }

                Text(synopsisText)
                    .font(.callout)
                    .lineSpacing(4)
                    .lineLimit(3)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: 680, alignment: .leading)

                HStack(spacing: DetailSpacing.sm) {
                    Button {
                        selectedTab = .episodes
                    } label: {
                        Label(episodes.isEmpty ? "Episodes unavailable" : "Select Episode", systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DetailActionStyle(variant: .primary))
                    .disabled(episodes.isEmpty)

                    Button {} label: {
                        Label("Favorite unavailable", systemImage: "heart")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(DetailActionStyle(variant: .icon))
                    .disabled(true)

                    Button {} label: {
                        Label("Download unavailable", systemImage: "arrow.down.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(DetailActionStyle(variant: .icon))
                    .disabled(true)
                }
                .frame(maxWidth: 620)
            }
            .padding(.horizontal, availableWidth < 700 ? 20 : 40)
            .padding(.bottom, DetailSpacing.xl)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .frame(height: height + topInset)
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
                        NavigationLink {
                            EpisodeDetailTile(series: currentSeries, episode: episode)
                        } label: {
                            SeriesEpisodeRow(episode: episode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let enrichmentError {
                Text("Episode metadata could not be refreshed: \(enrichmentError)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
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
        if let enrichmentError {
            return "The provider detail request failed before episode rows could be persisted locally: \(enrichmentError)"
        }
        return "No playable episode rows are stored locally for this series yet. If the provider exposes series details, this screen refreshes them through sync/detail enrichment and then renders the persisted rows."
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

    private func enrichCurrentSeries() async {
        do {
            try await session.enrichDetails(for: currentSeries)
            enrichmentError = nil
            synchronizeSelectedSeason()
        } catch is CancellationError {
            return
        } catch {
            enrichmentError = error.localizedDescription
        }
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
                progress: 1
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
        VStack(alignment: .leading, spacing: DetailSpacing.xs) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: DetailSpacing.md) {
                    Text(row.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 96, alignment: .leading)

                    selectableMetadataText(displayValue(for: row), isMissing: row.value == nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DetailSpacing.md)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
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
