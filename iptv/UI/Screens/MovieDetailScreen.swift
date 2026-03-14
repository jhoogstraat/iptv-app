//
//  MovieDetailScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 08.09.25.
//

import SwiftUI
import OSLog

private enum MovieDetailState {
    case fetching
    case error(Error)
    case done
}

struct MovieDetailScreen: View {
    let video: Video

    @Environment(Catalog.self) private var catalog
    @Environment(DownloadCenter.self) private var downloadCenter
    @Environment(Player.self) private var player
    @Environment(ProviderStore.self) private var providerStore
    @Environment(FavoritesStore.self) private var favoritesStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var state: MovieDetailState = .fetching
    @State private var playError: String?
    @State private var isFavorite = false
    @State private var offlineInfo: VideoInfo?
    @State private var offlineArtworkURL: URL?
    @State private var heroCollapseProgress: CGFloat = 0

    private var info: VideoInfo? {
        catalog.vodInfo[video]
    }

    private var resolvedInfo: VideoInfo? {
        info ?? offlineInfo
    }

    var body: some View {
        Group {
            switch state {
            case .fetching:
                ProgressView()

            case .error(let error):
                VStack(spacing: 12) {
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadInfo(policy: .refreshNow) }
                    }
                    .buttonStyle(DetailActionStyle(variant: .primary))
                }
                .padding()

            case .done:
                detailContent
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
            await loadInfo(policy: .cachedThenRefresh)
            await loadFavoriteState()
        }
    }

    private var detailContent: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                heroBackground(topInset: topInset)

                ScrollView {
                    VStack(spacing: 0) {
                        heroForeground(topInset: topInset)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: DetailHeroProgressPreferenceKey.self,
                                        value: geometry.frame(in: .named("movieDetailScroll")).minY
                                    )
                                }
                            )

                        DetailContentLayout(
                            isCompact: usesCompactDetailLayout,
                            availableWidth: usesCompactDetailLayout ? proxy.size.width : nil
                        ) {
                            primaryActions

                            if let playError {
                                Text(playError)
                                    .foregroundStyle(.red)
                            }

                            overviewText

                            if !scoreBadges.isEmpty {
                                ratingSection
                            }

                            section("Cast", text: resolvedInfo?.cast ?? "No cast information available.")
                            section("Director", text: resolvedInfo?.director ?? "No director information available.")
                            section("About", text: aboutText)
                        }
                        .background(Color.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .coordinateSpace(name: "movieDetailScroll")
                .scrollIndicators(.hidden)
                .onPreferenceChange(DetailHeroProgressPreferenceKey.self) { minY in
                    heroCollapseProgress = heroProgress(for: minY)
                }

                DetailCollapsedHeaderBar(
                    title: video.name,
                    artworkURL: collapsedArtworkURL,
                    titleArtworkURL: heroTitleArtworkURL,
                    progress: heroCollapseProgress
                )
                .padding(.top, topInset + 8)
            }
            .background(Color.black.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        VStack(spacing: 12) {
            playButton

            HStack(spacing: 12) {
                favoriteButton
                downloadButton
                refreshButton
            }
        }
    }

    private var playButton: some View {
        Button {
            startPlayback()
        } label: {
            Label("Continue Watching", systemImage: "play.fill")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DetailActionStyle(variant: .primary))
    }

    private var downloadButton: some View {
        DownloadStatusBadge(
            selection: .movie(video),
            showsTitle: false,
            presentation: .detailAction(.icon)
        )
    }

    private var favoriteButton: some View {
        Button {
            Task { await toggleFavorite() }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
        }
        .buttonStyle(DetailActionStyle(variant: .icon))
    }

    private var refreshButton: some View {
        Button {
            Task { await loadInfo(policy: .refreshNow) }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(DetailActionStyle(variant: .icon))
    }

    private var scoreBadges: [DetailScoreBadgeModel] {
        [
            DetailScoreSource.catalog.badgeModel(value: resolvedInfo?.rating)
        ]
        .compactMap { $0 }
    }

    private var heroHeight: CGFloat {
        usesCompactDetailLayout ? 430 : 520
    }

    private var heroArtworkURL: URL? {
        offlineArtworkURL ?? resolvedInfo?.images.first ?? URL(string: video.coverImageURL ?? "")
    }

    private var collapsedArtworkURL: URL? {
        URL(string: video.coverImageURL ?? "") ?? heroArtworkURL
    }

    private var heroTitleArtworkURL: URL? {
        guard let coverURL = URL(string: video.coverImageURL ?? ""),
              coverURL != heroArtworkURL else {
            return nil
        }
        return coverURL
    }

    private var heroGenreText: String? {
        let genres = resolvedInfo?.genre
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let genres, !genres.isEmpty else { return nil }
        return genres.joined(separator: " / ")
    }

    private var heroYearText: String? {
        yearText(from: resolvedInfo?.releaseDate)
    }

    private var heroRuntimeText: String? {
        if let durationLabel = resolvedInfo?.durationLabel,
           !durationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return durationLabel
        }
        if let runtimeMinutes = resolvedInfo?.runtimeMinutes {
            return "\(runtimeMinutes) min"
        }
        return nil
    }

    private var heroScoreText: String? {
        scoreBadges.first?.value
    }

    private var overviewText: some View {
        Text(resolvedInfo?.plot ?? "No synopsis available.")
            .font(.title3.weight(.regular))
            .lineSpacing(6)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(title: "Ratings")
            DetailScoreBadgeRow(badges: scoreBadges)
        }
    }

    private var aboutText: String {
        var lines: [String] = []
        if let country = resolvedInfo?.country, !country.isEmpty {
            lines.append("Country: \(country)")
        }
        if let runtimeMinutes = resolvedInfo?.runtimeMinutes {
            lines.append("Runtime: \(runtimeMinutes) min")
        }
        return lines.joined(separator: "\n")
    }

    private var usesCompactDetailLayout: Bool {
        horizontalSizeClass == .compact
    }

    @ViewBuilder
    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionHeader(title: title)
            Text(text.isEmpty ? "Not available." : text)
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    @ViewBuilder
    private func heroBackground(topInset: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if let heroArtworkURL {
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

    private func heroForeground(topInset: CGFloat) -> some View {
        VStack(spacing: 16) {
            Spacer()

            if let heroTitleArtworkURL {
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

            heroMetaRow

            if let heroGenreText {
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
    private var heroMetaRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                heroMetaItems
            }
            VStack(spacing: 10) {
                heroMetaItems
            }
        }
    }

    @ViewBuilder
    private var heroMetaItems: some View {
        if let heroScoreText {
            DetailMetaPill(heroScoreText, systemImage: "star.fill")
        }
        if let heroYearText {
            Text(heroYearText)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)
        }
        if let heroRuntimeText {
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

    private func loadInfo(policy: CatalogLoadPolicy = .cachedThenRefresh) async {
        guard policy == .refreshNow || (info == nil && offlineInfo == nil) else {
            state = .done
            return
        }

        do {
            state = .fetching
            try await catalog.getVodInfo(video, policy: policy)
            offlineArtworkURL = await downloadCenter.offlineArtworkURL(
                for: video,
                candidates: [info?.images.first?.absoluteString, video.coverImageURL]
            )
            state = .done
        } catch {
            if let offlineInfo = await downloadCenter.offlineMovieInfo(for: video) {
                self.offlineInfo = offlineInfo
                offlineArtworkURL = await downloadCenter.offlineArtworkURL(
                    for: video,
                    candidates: [offlineInfo.images.first?.absoluteString, video.coverImageURL]
                )
                state = .done
            } else {
                logger.error("Failed to load movie detail for \(video.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                state = .error(error)
            }
        }
    }

    private func startPlayback() {
        Task {
            do {
                let source = try await downloadCenter.playbackSource(for: video)
                playError = nil
                player.load(video, source, presentation: .fullWindow)
            } catch {
                playError = error.localizedDescription
                logger.error("Failed to resolve playback URL for \(video.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
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

#Preview(traits: .previewData) {
    NavigationStack {
        MovieDetailScreen(video: .init(id: 0, name: "EN - Title of the movie", containerExtension: "mkv", contentType: "movie", coverImageURL: "error_url", tmdbId: nil, rating: 7.7))
    }
    .frame(width: 390, height: 844)
}
