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

    private var contentLocale: Locale {
        .autoupdatingCurrent
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let loadError {
                VStack(spacing: 12) {
                    Text(loadError.localizedDescription)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadSeriesInfo(policy: .refreshNow) }
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
        .navigationTitle(video.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        #endif
        .withBackgroundActivityToolbar()
        .task {
            await loadSeriesInfo(policy: .cachedThenRefresh)
            await loadFavoriteState()
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
                    heroCollapseProgress = heroProgress(for: minY)
                }

                DetailCollapsedHeaderBar(
                    title: video.name,
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
        VStack(alignment: .leading, spacing: 16) {
            DetailSectionHeader(title: "Episodes")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sortedSeasonKeys(from: seriesInfo), id: \.self) { seasonKey in
                        seasonButton(for: seasonKey, in: seriesInfo)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(selectedSeasonEpisodes(from: seriesInfo), id: \.id) { episode in
                        if usesCompactDetailLayout {
                            episodeCard(episode: episode, seriesInfo: seriesInfo)
                                .id(episodeID(for: episode))
                                .containerRelativeFrame(.horizontal, count: 7, span: 5, spacing: 14, alignment: .leading)
                        } else {
                            episodeCard(episode: episode, seriesInfo: seriesInfo)
                                .id(episodeID(for: episode))
                                .frame(width: 288)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 4)
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

        return Button {
            selectedEpisodeID = episodeID(for: episode)
            startPlayback(episode: episode, seriesInfo: seriesInfo)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
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
                .clipShape(.rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text(episodeBadgeText(for: episode))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))

                    Text(episode.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(.white)

                    Text(episodeMetaText(for: episode))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.semibold))
                        Text(localized("Play Episode", comment: "Play a specific episode action"))
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.top, 4)
                    .foregroundStyle(.white.opacity(0.88))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.white.opacity(0.12)
                            : Color.white.opacity(0.06)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.10),
                        lineWidth: isSelected ? 1.25 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func primaryActions(seriesInfo: XtreamSeries) -> some View {
        VStack(spacing: 12) {
            playButton(seriesInfo: seriesInfo)

            HStack(spacing: 12) {
                bookmarkButton
                DownloadStatusBadge(
                    selection: .series(video),
                    showsTitle: false,
                    presentation: .detailAction(.icon)
                )
                refreshButton
            }
        }
    }

    @ViewBuilder
    private var selectionDownloads: some View {
        let seasonBadge = selectedSeasonDownloadBadge
        let episodeBadge = selectedEpisodeDownloadBadge

        if usesCompactDetailLayout {
            VStack(alignment: .leading, spacing: 12) {
                if let seasonBadge {
                    seasonBadge
                }

                if let episodeBadge {
                    episodeBadge
                }
            }
        } else {
            HStack(spacing: 12) {
                if let seasonBadge {
                    seasonBadge
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let episodeBadge {
                    episodeBadge
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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

    private var refreshButton: some View {
        Button {
            Task { await loadSeriesInfo(policy: .refreshNow) }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(DetailActionStyle(variant: .icon))
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

    private var selectedEpisodeDownloadBadge: AnyView? {
        guard let selectedEpisodeID else { return nil }
        return AnyView(
            DownloadStatusBadge(
                selection: .episode(seriesID: video.id, episodeID: selectedEpisodeID),
                showsTitle: true,
                presentation: .detailAction(.secondary)
            )
        )
    }

    @ViewBuilder
    private func seasonButton(for seasonKey: String, in seriesInfo: XtreamSeries) -> some View {
        let isSelected = seasonKey == selectedSeasonKey

        Button {
            selectedSeasonKey = seasonKey
            selectedEpisodeID = episodes(in: seasonKey, from: seriesInfo).first.map(episodeID(for:))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(seasonTitle(for: seasonKey, in: seriesInfo))
                Text(episodeCountText(episodes(in: seasonKey, from: seriesInfo).count))
                    .opacity(isSelected ? 0.78 : 0.72)
            }
            .frame(minWidth: 132, alignment: .leading)
        }
        .buttonStyle(DetailActionStyle(variant: .chip(selected: isSelected)))
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
        VStack(alignment: .leading, spacing: 8) {
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

    private func episodeMetaText(for episode: XtreamEpisode) -> String {
        [
            episodeShortLabel(for: episode),
            normalizedText(episode.info.duration),
            normalizedText(episode.info.airDate)
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
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
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(title: "Ratings")
            DetailScoreBadgeRow(badges: scoreBadges(for: seriesInfo))
        }
    }

    @ViewBuilder
    private func heroBackground(seriesInfo: XtreamSeries, topInset: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if let heroArtworkURL = heroArtworkURL(for: seriesInfo) {
                AsyncImage(url: heroArtworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Color.white.opacity(0.05)
                    }
                }
            } else {
                Color.white.opacity(0.05)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.28),
                    Color.black.opacity(0.68),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: heroHeight + topInset)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay {
            Color.black.opacity(Double(heroCollapseProgress) * 0.36)
        }
        .opacity(1.0 - (Double(heroCollapseProgress) * 0.92))
        .ignoresSafeArea(edges: .top)
    }

    private func heroForeground(seriesInfo: XtreamSeries, topInset: CGFloat) -> some View {
        VStack(spacing: 16) {
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

            Text(video.name)
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
        .padding(.bottom, 28)
        .opacity(1.0 - (Double(heroCollapseProgress) * 0.94))
        .offset(y: -(heroCollapseProgress * 18))
    }

    @ViewBuilder
    private func heroMetaRow(seriesInfo: XtreamSeries) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                heroMetaItems(seriesInfo: seriesInfo)
            }
            VStack(spacing: 10) {
                heroMetaItems(seriesInfo: seriesInfo)
            }
        }
    }

    @ViewBuilder
    private func heroMetaItems(seriesInfo: XtreamSeries) -> some View {
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

    private func loadSeriesInfo(policy: CatalogLoadPolicy = .cachedThenRefresh) async {
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
}

#Preview {
    NavigationStack {
        EpisodeDetailTile(video: .init(id: 10, name: "Example Series", containerExtension: "mp4", contentType: XtreamContentType.series.rawValue, coverImageURL: nil, tmdbId: nil, rating: nil))
    }
    .frame(width: 390, height: 844)
}
