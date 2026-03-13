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
                    .buttonStyle(.borderedProminent)
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
        .withBackgroundActivityToolbar()
        .task {
            await loadSeriesInfo(policy: .cachedThenRefresh)
            await loadFavoriteState()
        }
    }

    @ViewBuilder
    private func detailContent(seriesInfo: XtreamSeries) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerArtwork(seriesInfo: seriesInfo)

                VStack(alignment: .leading, spacing: 12) {
                    Text(video.name)
                        .font(.title.weight(.semibold))

                    Text(subtitleText(for: seriesInfo))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    primaryActions(seriesInfo: seriesInfo)
                    selectionDownloads
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let playError {
                    Text(playError)
                        .foregroundStyle(.red)
                }

                section("Synopsis", text: seriesInfo.info.plot)
                episodeBrowser(seriesInfo: seriesInfo)
                section("Cast", text: seriesInfo.info.cast)
                section("Director", text: seriesInfo.info.director)
                section("About", text: aboutText(for: seriesInfo))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headerArtwork(seriesInfo: XtreamSeries) -> some View {
        Group {
            if let heroURL = offlineHeaderArtworkURL ?? headerArtworkURL(for: seriesInfo) {
                AsyncImage(url: heroURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .boundedFillArtwork()
                    default:
                        placeholderArtwork(systemImage: "tv")
                    }
                }
            } else {
                placeholderArtwork(systemImage: "tv")
            }
        }
        .frame(height: 260)
        .clipShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func episodeBrowser(seriesInfo: XtreamSeries) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Episodes", comment: "Episodes section title"))
                .font(.title3.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sortedSeasonKeys(from: seriesInfo), id: \.self) { seasonKey in
                        seasonButton(for: seasonKey, in: seriesInfo)
                    }
                }
                .padding(.vertical, 2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(selectedSeasonEpisodes(from: seriesInfo), id: \.id) { episode in
                        episodeCard(episode: episode, seriesInfo: seriesInfo)
                            .id(episodeID(for: episode))
                            .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: 0, alignment: .center)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $selectedEpisodeID)
        }
    }

    private func episodeCard(episode: XtreamEpisode, seriesInfo: XtreamSeries) -> some View {
        let isSelected = selectedEpisodeID == episodeID(for: episode)
        let artworkURL = episodeArtworkURL(for: episode, seriesInfo: seriesInfo)
        let cardWidth: CGFloat = usesCompactDetailLayout ? 280 : 304

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
                .frame(width: cardWidth - 24, height: (cardWidth - 24) * 0.564)
                .clipShape(.rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text(episodeBadgeText(for: episode))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(episode.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(episodeMetaText(for: episode))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.semibold))
                        Text(localized("Play Episode", comment: "Play a specific episode action"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(width: cardWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.16), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func primaryActions(seriesInfo: XtreamSeries) -> some View {
        if usesCompactDetailLayout {
            VStack(spacing: 12) {
                playButton(seriesInfo: seriesInfo)

                HStack(spacing: 12) {
                    DownloadStatusBadge(selection: .series(video), showsTitle: true)
                        .frame(maxWidth: .infinity)
                    bookmarkButton
                }
            }
        } else {
            HStack(spacing: 12) {
                playButton(seriesInfo: seriesInfo)
                DownloadStatusBadge(selection: .series(video), showsTitle: true)
                    .frame(maxWidth: .infinity)
                bookmarkButton
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
        .buttonStyle(.borderedProminent)
        .disabled(selectedEpisode(from: seriesInfo) == nil)
    }

    private var bookmarkButton: some View {
        Button {
            Task { await toggleFavorite() }
        } label: {
            Label(bookmarkActionTitle, systemImage: isFavorite ? "bookmark.fill" : "bookmark")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var selectedSeasonDownloadBadge: AnyView? {
        guard let seasonNumber = selectedSeasonNumber else { return nil }
        return AnyView(
            DownloadStatusBadge(
                selection: .season(seriesID: video.id, seasonNumber: seasonNumber),
                showsTitle: true
            )
        )
    }

    private var selectedEpisodeDownloadBadge: AnyView? {
        guard let selectedEpisodeID else { return nil }
        return AnyView(
            DownloadStatusBadge(
                selection: .episode(seriesID: video.id, episodeID: selectedEpisodeID),
                showsTitle: true
            )
        )
    }

    @ViewBuilder
    private func seasonButton(for seasonKey: String, in seriesInfo: XtreamSeries) -> some View {
        let isSelected = seasonKey == selectedSeasonKey

        let button = Button {
            selectedSeasonKey = seasonKey
            selectedEpisodeID = episodes(in: seasonKey, from: seriesInfo).first.map(episodeID(for:))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(seasonTitle(for: seasonKey, in: seriesInfo))
                Text(episodeCountText(episodes(in: seasonKey, from: seriesInfo).count))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 150, alignment: .leading)
        }
        .controlSize(.large)

        if isSelected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
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

    private func subtitleText(for seriesInfo: XtreamSeries) -> String {
        [
            normalizedText(seriesInfo.info.genre),
            normalizedText(seriesInfo.info.releaseDate),
            seasonCountText(for: seriesInfo)
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    private func aboutText(for seriesInfo: XtreamSeries) -> String {
        var lines: [String] = []

        if let rating = normalizedText(seriesInfo.info.rating) {
            lines.append("Rating: \(rating)")
        }
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
            Text(localized(title, comment: "Series detail section title"))
                .font(.title3.weight(.semibold))
            Text(normalizedText(text) ?? localized("Not available.", comment: "Fallback when metadata is missing"))
                .foregroundStyle(.secondary)
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

    private func seasonCountText(for seriesInfo: XtreamSeries) -> String? {
        let count = seriesInfo.seasons.count
        guard count > 0 else { return nil }
        return count == 1
            ? localized("1 season", comment: "Single season count")
            : String(localized: "\(count) seasons", locale: contentLocale, comment: "Plural season count")
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

    private var bookmarkActionTitle: String {
        isFavorite
            ? localized("Remove Bookmark", comment: "Remove the series from bookmarks")
            : localized("Save Bookmark", comment: "Save the series to bookmarks")
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
    EpisodeDetailTile(video: .init(id: 10, name: "Example Series", containerExtension: "mp4", contentType: XtreamContentType.series.rawValue, coverImageURL: nil, tmdbId: nil, rating: nil))
}
