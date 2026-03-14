//
//  EpisodeDetailTile.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 08.09.25.
//

import SwiftUI
import OSLog

struct EpisodeDetailTile: View {
    let video: Video

    @Environment(Catalog.self) private var catalog
    @Environment(DownloadCenter.self) private var downloadCenter
    @Environment(Player.self) private var player
    @Environment(ProviderStore.self) private var providerStore
    @Environment(FavoritesStore.self) private var favoritesStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var seriesInfo: XtreamSeries?
    @State private var playError: String?
    @State private var isFavorite = false
    @State private var selectedSeasonKey: String?
    @State private var selectedEpisodeID: Int?
    @State private var offlineHeaderArtworkURL: URL?
    @State private var heroCollapseProgress: CGFloat = 0
    @State private var heroScrollOffset: CGFloat = 0
    @State private var isShowingOtherSources = false
    @State private var isLoadingOtherSources = false
    @State private var otherSources: [DetailAlternativeSource] = []
    @State private var otherSourcesError: String?
    @State private var episodeProgressByID: [Int: WatchProgressSnapshot] = [:]

    private var contentLocale: Locale {
        .autoupdatingCurrent
    }

    private var displayTitle: String {
        LanguageTaggedText(video.name).groupedDisplayName
    }

    private var heroLanguageText: String? {
        LanguageTaggedText(video.name).languageCode
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let loadError {
                VStack(spacing: DetailSpacing.sm) {
                    Text(loadError.localizedDescription)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadSeriesInfo(policy: .forceRefresh) }
                    }
                    .buttonStyle(DetailActionStyle(variant: .primary))
                }
                .padding()
            } else if let seriesInfo {
                detailContent(seriesInfo: seriesInfo)
            } else {
                Text(localized("Series details are unavailable.", comment: "Fallback message when series details cannot be shown"))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(displayTitle)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        #endif
        .withBackgroundActivityToolbar()
        .sheet(isPresented: $isShowingOtherSources) {
            DetailAlternativeSourcesSheet(
                title: "Other Sources",
                isLoading: isLoadingOtherSources,
                errorMessage: otherSourcesError,
                sources: otherSources,
                onRetry: { triggerOtherSourcesLookup() },
                destination: { EpisodeDetailTile(video: $0) }
            )
        }
        .task {
            await loadSeriesInfo(policy: .readThrough)
            await loadFavoriteState()
            await loadEpisodeProgressState()
        }
    }

    @ViewBuilder
    private func detailContent(seriesInfo: XtreamSeries) -> some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                heroBackground(seriesInfo: seriesInfo, topInset: topInset)

                ScrollView {
                    VStack(spacing: 0) {
                        heroForeground(seriesInfo: seriesInfo, topInset: topInset)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: DetailHeroProgressPreferenceKey.self,
                                        value: geometry.frame(in: .named("seriesDetailScroll")).minY
                                    )
                                }
                            )

                        DetailContentLayout(
                            isCompact: usesCompactDetailLayout,
                            availableWidth: usesCompactDetailLayout ? proxy.size.width : nil
                        ) {
                            primaryActions(seriesInfo: seriesInfo)

                            if let playError {
                                Text(playError)
                                    .foregroundStyle(.red)
                            }

                            overviewText(seriesInfo: seriesInfo)

                            if !scoreBadges(for: seriesInfo).isEmpty {
                                ratingSection(seriesInfo: seriesInfo)
                            }

                            episodeBrowser(seriesInfo: seriesInfo)
                            selectionDownloads
                            section("Cast", text: seriesInfo.info.cast)
                            section("Director", text: seriesInfo.info.director)
                            section("About", text: aboutText(for: seriesInfo))
                        }
                        .background(Color.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .coordinateSpace(name: "seriesDetailScroll")
                .scrollIndicators(.hidden)
                .onPreferenceChange(DetailHeroProgressPreferenceKey.self) { minY in
                    heroScrollOffset = minY
                    heroCollapseProgress = heroProgress(for: minY)
                }

                DetailCollapsedHeaderBar(
                    title: displayTitle,
                    artworkURL: collapsedArtworkURL(for: seriesInfo),
                    titleArtworkURL: heroTitleArtworkURL(for: seriesInfo),
                    progress: heroCollapseProgress
                )
                .padding(.top, topInset + 8)
            }
            .background(Color.black.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private func episodeBrowser(seriesInfo: XtreamSeries) -> some View {
        VStack(alignment: .leading, spacing: DetailSpacing.md) {
            DetailSectionHeader(title: "Episodes")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DetailSpacing.xs) {
                    ForEach(sortedSeasonKeys(from: seriesInfo), id: \.self) { seasonKey in
                        seasonButton(for: seasonKey, in: seriesInfo)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DetailSpacing.sm) {
                    ForEach(selectedSeasonEpisodes(from: seriesInfo), id: \.id) { episode in
                        if usesCompactDetailLayout {
                            episodeCard(episode: episode, seriesInfo: seriesInfo)
                                .id(episodeID(for: episode))
                                .containerRelativeFrame(.horizontal, count: 7, span: 5, spacing: DetailSpacing.sm, alignment: .leading)
                        } else {
                            episodeCard(episode: episode, seriesInfo: seriesInfo)
                                .id(episodeID(for: episode))
                                .frame(width: 288)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, DetailSpacing.xxs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $selectedEpisodeID)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func episodeCard(episode: XtreamEpisode, seriesInfo: XtreamSeries) -> some View {
        let isSelected = selectedEpisodeID == episodeID(for: episode)
        let artworkURL = episodeArtworkURL(for: episode, seriesInfo: seriesInfo)
        let progress = episodeProgress(for: episode)

        return VStack(alignment: .leading, spacing: DetailSpacing.sm) {
            Group {
                if let artworkURL {
                    AsyncImage(url: artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .boundedCoverArtwork()
                        default:
                            placeholderArtwork(systemImage: "play.rectangle")
                        }
                    }
                } else {
                    placeholderArtwork(systemImage: "play.rectangle")
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: DetailSpacing.xs) {
                Text(episodeBadgeText(for: episode))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))

                Text(episode.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.white)

                HStack(spacing: DetailSpacing.xs) {
                    if let runtimeText = episodeRuntimeText(for: episode, seriesInfo: seriesInfo) {
                        Label(runtimeText, systemImage: "clock")
                    }

                    if let airDateText = episodeAirDateText(for: episode) {
                        Label(airDateText, systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)

                episodeProgressSection(progress)

                HStack(spacing: DetailSpacing.xs) {
                    playEpisodeButton(episode: episode, seriesInfo: seriesInfo)

                    DownloadStatusBadge(
                        selection: .episode(seriesID: video.id, episodeID: episodeID(for: episode)),
                        showsTitle: true,
                        presentation: .detailAction(.compactSecondary),
                        labelOverride: "Download"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    isSelected
                        ? Color.white.opacity(0.12)
                        : Color.white.opacity(0.06)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isSelected ? Color.white.opacity(0.20) : Color.white.opacity(0.10),
                    lineWidth: isSelected ? 1.25 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            selectedEpisodeID = episodeID(for: episode)
        }
    }

    @ViewBuilder
    private func episodeProgressSection(_ progress: WatchProgressSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: DetailSpacing.xxs + DetailSpacing.xxs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    if let progress {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.84))
                            .frame(width: max(geometry.size.width * progress.progressFraction, progress.progressFraction > 0 ? 6 : 0))
                    }
                }
            }
            .frame(height: 4)

            Text(progressStatusText(progress))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.52))
        }
    }

    private func playEpisodeButton(episode: XtreamEpisode, seriesInfo: XtreamSeries) -> some View {
        Button {
            selectedEpisodeID = episodeID(for: episode)
            startPlayback(episode: episode, seriesInfo: seriesInfo)
        } label: {
            Label("Play", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DetailActionStyle(variant: .compactPrimary))
    }

    @ViewBuilder
    private func primaryActions(seriesInfo: XtreamSeries) -> some View {
        HStack(spacing: DetailSpacing.sm) {
            playButton(seriesInfo: seriesInfo)
            bookmarkButton
            DownloadStatusBadge(
                selection: .series(video),
                showsTitle: false,
                presentation: .detailAction(.icon)
            )
            otherSourcesButton
        }
    }

    @ViewBuilder
    private var selectionDownloads: some View {
        if let seasonBadge = selectedSeasonDownloadBadge {
            seasonBadge
        }
    }

    private func playButton(seriesInfo: XtreamSeries) -> some View {
        Button {
            playSelectedEpisode(from: seriesInfo)
        } label: {
            Label(primaryActionTitle(for: seriesInfo), systemImage: "play.fill")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DetailActionStyle(variant: .primary))
        .disabled(selectedEpisode(from: seriesInfo) == nil)
    }

    private var bookmarkButton: some View {
        Button {
            Task { await toggleFavorite() }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
        }
        .buttonStyle(DetailActionStyle(variant: .icon))
    }

    private var otherSourcesButton: some View {
        Button {
            triggerOtherSourcesLookup()
        } label: {
            if isLoadingOtherSources {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: "square.stack.3d.up")
            }
        }
        .buttonStyle(DetailActionStyle(variant: .icon))
        .accessibilityLabel("Other Sources")
    }

    private var selectedSeasonDownloadBadge: AnyView? {
        guard let seasonNumber = selectedSeasonNumber else { return nil }
        return AnyView(
            DownloadStatusBadge(
                selection: .season(seriesID: video.id, seasonNumber: seasonNumber),
                showsTitle: true,
                presentation: .detailAction(.secondary)
            )
        )
    }

    @ViewBuilder
    private func seasonButton(for seasonKey: String, in seriesInfo: XtreamSeries) -> some View {
        let isSelected = seasonKey == selectedSeasonKey
        let episodesCount = episodes(in: seasonKey, from: seriesInfo).count

        Button {
            selectedSeasonKey = seasonKey
            selectedEpisodeID = episodes(in: seasonKey, from: seriesInfo).first.map(episodeID(for:))
        } label: {
            VStack(alignment: .leading, spacing: DetailSpacing.xxxs) {
                Text(seasonTitle(for: seasonKey, in: seriesInfo))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(episodeCountText(episodesCount))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(isSelected ? 0.74 : 0.56))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, DetailSpacing.xs + DetailSpacing.xxxs)
            .frame(minWidth: episodesCount > 9 ? 114 : 98, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.10),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func placeholderArtwork(systemImage: String) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }

    private func aboutText(for seriesInfo: XtreamSeries) -> String {
        var lines: [String] = []

        if let tmdb = normalizedText(seriesInfo.info.tmdb) {
            lines.append("TMDB: \(tmdb)")
        }
        lines.append("Seasons: \(seriesInfo.seasons.count)")
        lines.append("Episodes: \(allEpisodes(from: seriesInfo).count)")

        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DetailSpacing.xs) {
            DetailSectionHeader(title: title)
            Text(normalizedText(text) ?? localized("Not available.", comment: "Fallback when metadata is missing"))
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func sortedSeasonKeys(from seriesInfo: XtreamSeries) -> [String] {
        seriesInfo.episodes.keys.sorted { lhs, rhs in
            (Int(lhs) ?? 0) < (Int(rhs) ?? 0)
        }
    }

    private func episodes(in seasonKey: String, from seriesInfo: XtreamSeries) -> [XtreamEpisode] {
        (seriesInfo.episodes[seasonKey] ?? []).sorted { lhs, rhs in
            lhs.episodeNum < rhs.episodeNum
        }
    }

    private func allEpisodes(from seriesInfo: XtreamSeries) -> [XtreamEpisode] {
        sortedSeasonKeys(from: seriesInfo)
            .flatMap { episodes(in: $0, from: seriesInfo) }
    }

    private func selectedSeasonEpisodes(from seriesInfo: XtreamSeries) -> [XtreamEpisode] {
        guard let seasonKey = selectedSeasonKey ?? sortedSeasonKeys(from: seriesInfo).first else {
            return []
        }
        return episodes(in: seasonKey, from: seriesInfo)
    }

    private func selectedEpisode(from seriesInfo: XtreamSeries) -> XtreamEpisode? {
        let seasonEpisodes = selectedSeasonEpisodes(from: seriesInfo)
        if let selectedEpisodeID {
            return seasonEpisodes.first(where: { episodeID(for: $0) == selectedEpisodeID }) ?? seasonEpisodes.first
        }
        return seasonEpisodes.first
    }

    private func episodeVideos(from seriesInfo: XtreamSeries) -> [Video] {
        allEpisodes(from: seriesInfo).map(Video.init(from:))
    }

    private func episodeID(for episode: XtreamEpisode) -> Int {
        Int(episode.id) ?? episode.info.id
    }

    private func primaryActionTitle(for seriesInfo: XtreamSeries) -> String {
        guard let episode = selectedEpisode(from: seriesInfo) else {
            return localized("Play", comment: "Generic play action")
        }
        return String(
            localized: "Play E\(episode.episodeNum)",
            locale: contentLocale,
            comment: "Primary action to play the selected episode"
        )
    }

    private func seasonTitle(for seasonKey: String, in seriesInfo: XtreamSeries) -> String {
        if let seasonNumber = Int(seasonKey),
           let season = seriesInfo.seasons.first(where: { $0.seasonNumber == seasonNumber }),
           let seasonName = normalizedText(season.name) {
            return seasonName
        }
        return String(
            localized: "Season \(seasonKey)",
            locale: contentLocale,
            comment: "Season title in the episode browser"
        )
    }

    private func scoreBadges(for seriesInfo: XtreamSeries) -> [DetailScoreBadgeModel] {
        [
            DetailScoreSource.catalog.badgeModel(text: normalizedText(seriesInfo.info.rating))
        ]
        .compactMap { $0 }
    }

    private var heroHeight: CGFloat {
        usesCompactDetailLayout ? 430 : 520
    }

    private func heroArtworkURL(for seriesInfo: XtreamSeries) -> URL? {
        offlineHeaderArtworkURL ?? headerArtworkURL(for: seriesInfo)
    }

    private func collapsedArtworkURL(for seriesInfo: XtreamSeries) -> URL? {
        URL(string: video.coverImageURL ?? "") ?? heroArtworkURL(for: seriesInfo)
    }

    private func heroTitleArtworkURL(for seriesInfo: XtreamSeries) -> URL? {
        guard let coverURL = URL(string: normalizedText(seriesInfo.info.cover) ?? video.coverImageURL ?? ""),
              coverURL != heroArtworkURL(for: seriesInfo) else {
            return nil
        }
        return coverURL
    }

    private func heroGenreText(for seriesInfo: XtreamSeries) -> String? {
        let genres = normalizedText(seriesInfo.info.genre)?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let genres, !genres.isEmpty else { return nil }
        return genres.joined(separator: " / ")
    }

    private func heroYearText(for seriesInfo: XtreamSeries) -> String? {
        yearText(from: normalizedText(seriesInfo.info.releaseDate))
    }

    private func heroRuntimeText(for seriesInfo: XtreamSeries) -> String? {
        if let selectedDuration = normalizedText(selectedEpisode(from: seriesInfo)?.info.duration) {
            return selectedDuration
        }
        if let episodeRuntime = normalizedText(seriesInfo.info.episodeRunTime) {
            return "\(episodeRuntime) min"
        }
        return nil
    }

    private func heroScoreText(for seriesInfo: XtreamSeries) -> String? {
        scoreBadges(for: seriesInfo).first?.value
    }

    private func overviewText(seriesInfo: XtreamSeries) -> some View {
        Text(normalizedText(seriesInfo.info.plot) ?? localized("Not available.", comment: "Fallback when metadata is missing"))
            .font(.title3.weight(.regular))
            .lineSpacing(6)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ratingSection(seriesInfo: XtreamSeries) -> some View {
        VStack(alignment: .leading, spacing: DetailSpacing.sm) {
            DetailSectionHeader(title: "Ratings")
            DetailScoreBadgeRow(badges: scoreBadges(for: seriesInfo))
        }
    }

    @ViewBuilder
    private func heroBackground(seriesInfo: XtreamSeries, topInset: CGFloat) -> some View {
        DetailHeroBackdrop(
            artworkURL: heroArtworkURL(for: seriesInfo),
            height: heroHeight,
            topInset: topInset,
            collapseProgress: heroCollapseProgress,
            scrollOffset: heroScrollOffset
        )
    }

    private func heroForeground(seriesInfo: XtreamSeries, topInset: CGFloat) -> some View {
        VStack(spacing: DetailSpacing.md) {
            Spacer()

            if let heroTitleArtworkURL = heroTitleArtworkURL(for: seriesInfo) {
                AsyncImage(url: heroTitleArtworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: 240, maxHeight: 96)
                .shadow(color: Color.black.opacity(0.28), radius: 20, y: 10)
            }

            Text(displayTitle)
                .font(.system(size: usesCompactDetailLayout ? 42 : 56, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.24), radius: 14, y: 8)

            heroMetaRow(seriesInfo: seriesInfo)

            if let heroGenreText = heroGenreText(for: seriesInfo) {
                Text(heroGenreText)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(maxWidth: .infinity, minHeight: heroHeight + topInset, alignment: .bottom)
        .padding(.horizontal, usesCompactDetailLayout ? 24 : 32)
        .padding(.top, topInset + 24)
        .padding(.bottom, DetailSpacing.lg)
        .opacity(1.0 - (Double(heroCollapseProgress) * 0.94))
        .offset(y: -(heroCollapseProgress * 18))
    }

    @ViewBuilder
    private func heroMetaRow(seriesInfo: XtreamSeries) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DetailSpacing.sm) {
                heroMetaItems(seriesInfo: seriesInfo)
            }
            VStack(spacing: DetailSpacing.xs) {
                heroMetaItems(seriesInfo: seriesInfo)
            }
        }
    }

    @ViewBuilder
    private func heroMetaItems(seriesInfo: XtreamSeries) -> some View {
        if let heroLanguageText {
            Text(heroLanguageText)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
        }
        if let heroScoreText = heroScoreText(for: seriesInfo) {
            DetailMetaPill(heroScoreText, systemImage: "star.fill")
        }
        if let heroYearText = heroYearText(for: seriesInfo) {
            Text(heroYearText)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)
        }
        if let heroRuntimeText = heroRuntimeText(for: seriesInfo) {
            Text(heroRuntimeText)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
        }
    }

    private func heroProgress(for minY: CGFloat) -> CGFloat {
        let distance = max(heroHeight - 140, 1)
        return min(max(-minY / distance, 0), 1)
    }

    private func yearText(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let digits = rawValue.filter(\.isNumber)
        guard digits.count >= 4 else { return nil }
        return String(digits.prefix(4))
    }

    private func headerArtworkURL(for seriesInfo: XtreamSeries) -> URL? {
        let candidates = [
            seriesInfo.info.backdropPath.first,
            normalizedText(seriesInfo.info.cover),
            video.coverImageURL
        ]

        return candidates
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }

    private func episodeArtworkURL(for episode: XtreamEpisode, seriesInfo: XtreamSeries) -> URL? {
        let candidates = [
            normalizedText(episode.info.movieImage),
            normalizedText(seriesInfo.info.cover),
            video.coverImageURL
        ]

        return candidates
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func localized(_ key: String, comment: StaticString) -> String {
        String(localized: String.LocalizationValue(key), locale: contentLocale, comment: comment)
    }

    private func episodeCountText(_ count: Int) -> String {
        count == 1
            ? localized("1 episode", comment: "Single episode count")
            : String(localized: "\(count) episodes", locale: contentLocale, comment: "Plural episode count")
    }

    private func episodeShortLabel(for episode: XtreamEpisode) -> String {
        String(localized: "E\(episode.episodeNum)", locale: contentLocale, comment: "Short episode label")
    }

    private func episodeBadgeText(for episode: XtreamEpisode) -> String {
        String(localized: "Episode \(episode.episodeNum)", locale: contentLocale, comment: "Episode card title label")
    }

    private func episodeRuntimeText(for episode: XtreamEpisode, seriesInfo: XtreamSeries) -> String? {
        if let durationSeconds = episode.info.durationSecs {
            return friendlyDurationText(seconds: Double(durationSeconds))
        }

        if let duration = normalizedText(episode.info.duration),
           let parsedSeconds = parseDurationSeconds(duration) {
            return friendlyDurationText(seconds: parsedSeconds)
        }

        if let fallbackMinutes = Int(normalizedText(seriesInfo.info.episodeRunTime) ?? "") {
            return friendlyDurationText(seconds: Double(fallbackMinutes * 60))
        }

        return nil
    }

    private func episodeAirDateText(for episode: XtreamEpisode) -> String? {
        yearText(from: normalizedText(episode.info.airDate))
    }

    private func episodeProgress(for episode: XtreamEpisode) -> WatchProgressSnapshot? {
        episodeProgressByID[episodeID(for: episode)]
    }

    private func progressStatusText(_ progress: WatchProgressSnapshot?) -> String {
        guard let progress else {
            return "Not started"
        }

        if progress.isCompleted {
            return "Completed"
        }

        if let remaining = progress.remainingSeconds {
            return "\(friendlyDurationText(seconds: remaining)) left"
        }

        return "\(Int(progress.progressFraction * 100))% watched"
    }

    private func friendlyDurationText(seconds: Double) -> String {
        let totalMinutes = max(Int(seconds / 60), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)min"
        }

        return "\(totalMinutes)min"
    }

    private func parseDurationSeconds(_ duration: String) -> Double? {
        let components = duration
            .split(separator: ":")
            .compactMap { Int($0) }

        guard !components.isEmpty else { return nil }

        switch components.count {
        case 3:
            return Double((components[0] * 3600) + (components[1] * 60) + components[2])
        case 2:
            return Double((components[0] * 60) + components[1])
        case 1:
            return Double(components[0] * 60)
        default:
            return nil
        }
    }

    private func playSelectedEpisode(from seriesInfo: XtreamSeries) {
        guard let episode = selectedEpisode(from: seriesInfo) else { return }
        selectedEpisodeID = episodeID(for: episode)
        startPlayback(episode: episode, seriesInfo: seriesInfo)
    }

    private var selectedSeasonNumber: Int? {
        guard let selectedSeasonKey else { return nil }
        return Int(selectedSeasonKey)
    }

    private var usesCompactDetailLayout: Bool {
        horizontalSizeClass == .compact
    }

    private func startPlayback(episode: XtreamEpisode, seriesInfo: XtreamSeries) {
        let candidates = episodeVideos(from: seriesInfo)
        let episodeID = episodeID(for: episode)
        guard let selected = candidates.first(where: { $0.id == episodeID }) else { return }

        Task {
            do {
                player.configureEpisodeSwitcher(episodes: candidates) { episodeVideo in
                    try await downloadCenter.playbackSource(for: episodeVideo)
                }

                let source = try await downloadCenter.playbackSource(for: selected)
                playError = nil
                player.load(selected, source, presentation: .fullWindow)
            } catch {
                playError = error.localizedDescription
                logger.error("Failed to start episode playback for \(episode.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func loadSeriesInfo(policy: CatalogLoadPolicy = .readThrough) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedSeriesInfo = try await catalog.getSeriesInfo(video, policy: policy)
            seriesInfo = loadedSeriesInfo
            offlineHeaderArtworkURL = await downloadCenter.offlineArtworkURL(
                for: video,
                candidates: [
                    loadedSeriesInfo.info.backdropPath.first,
                    normalizedText(loadedSeriesInfo.info.cover),
                    video.coverImageURL
                ]
            )
            syncSelection(with: loadedSeriesInfo)
            loadError = nil
        } catch {
            if let offlineSeriesInfo = await downloadCenter.offlineSeriesInfo(for: video) {
                seriesInfo = offlineSeriesInfo
                offlineHeaderArtworkURL = await downloadCenter.offlineArtworkURL(
                    for: video,
                    candidates: [
                        offlineSeriesInfo.info.backdropPath.first,
                        normalizedText(offlineSeriesInfo.info.cover),
                        video.coverImageURL
                    ]
                )
                syncSelection(with: offlineSeriesInfo)
                loadError = nil
            } else {
                loadError = error
                logger.error("Failed to load series detail for \(video.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func syncSelection(with seriesInfo: XtreamSeries) {
        let seasonKeys = sortedSeasonKeys(from: seriesInfo)
        guard !seasonKeys.isEmpty else {
            selectedSeasonKey = nil
            selectedEpisodeID = nil
            return
        }

        if selectedSeasonKey == nil || !seasonKeys.contains(selectedSeasonKey ?? "") {
            selectedSeasonKey = seasonKeys[0]
        }

        let seasonEpisodes = selectedSeasonEpisodes(from: seriesInfo)
        if selectedEpisodeID == nil || !seasonEpisodes.contains(where: { episodeID(for: $0) == selectedEpisodeID }) {
            selectedEpisodeID = seasonEpisodes.first.map(episodeID(for:))
        }
    }

    private func loadFavoriteState() async {
        guard let config = try? providerStore.requiredConfiguration() else {
            isFavorite = false
            return
        }

        let fingerprint = ProviderCacheFingerprint.make(from: config)
        isFavorite = await favoritesStore.contains(video: video, providerFingerprint: fingerprint)
    }

    private func toggleFavorite() async {
        guard let config = try? providerStore.requiredConfiguration() else { return }

        let fingerprint = ProviderCacheFingerprint.make(from: config)
        let targetState = !isFavorite
        await favoritesStore.setFavorite(video: video, providerFingerprint: fingerprint, isFavorite: targetState)
        isFavorite = targetState
    }

    private func loadEpisodeProgressState() async {
        guard let config = try? providerStore.requiredConfiguration() else {
            episodeProgressByID = [:]
            return
        }

        let providerFingerprint = ProviderCacheFingerprint.make(from: config)
        let records = await DiskWatchActivityStore.shared.loadAll()
        let relevantRecords = records.filter {
            $0.providerFingerprint == providerFingerprint
                && $0.contentType == XtreamContentType.series.rawValue
        }

        episodeProgressByID = Dictionary(
            uniqueKeysWithValues: relevantRecords.map { ($0.videoID, $0.progress) }
        )
    }

    private func triggerOtherSourcesLookup() {
        isShowingOtherSources = true
        guard !isLoadingOtherSources else { return }

        Task {
            await loadOtherSources()
        }
    }

    private func loadOtherSources() async {
        isLoadingOtherSources = true
        otherSourcesError = nil

        do {
            otherSources = try await loadDetailAlternativeSources(
                for: video,
                preferredTitle: normalizedText(seriesInfo?.info.name) ?? video.name,
                catalog: catalog
            )
        } catch {
            otherSources = []
            otherSourcesError = error.localizedDescription
        }

        isLoadingOtherSources = false
    }
}

#Preview {
    NavigationStack {
        EpisodeDetailTile(video: .init(id: 10, name: "Example Series", containerExtension: "mp4", contentType: XtreamContentType.series.rawValue, coverImageURL: nil, tmdbId: nil, rating: nil))
    }
    .frame(width: 390, height: 844)
}
