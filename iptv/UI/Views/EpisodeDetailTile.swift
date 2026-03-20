//
//  EpisodeDetailTile.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 08.09.25.
//

import SwiftUI
import SwiftData
import OSLog

struct EpisodeDetailTile: View {
    let series: Series
    let episode: Episode

    @Environment(Player.self) private var player
//    @Environment(ActiveSession.self) private var session
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var playError: String?
    @State private var isFavorite = false
    @State private var selectedSeasonId: Season.ID?
    @State private var selectedEpisodeId: Episode.ID?
    @State private var offlineHeaderArtworkURL: URL?
    @State private var heroCollapseProgress: CGFloat = 0
    @State private var heroScrollOffset: CGFloat = 0
    @State private var isShowingOtherSources = false
    @State private var isLoadingOtherSources = false
    @State private var otherSources: [DetailAlternativeSource] = []
    @State private var otherSourcesError: String?

    private var displayTitle: String {
        episode.name
    }

    private var heroLanguageText: String? {
        episode.name
    }

    var body: some View {
        detailContent()
            .navigationTitle(displayTitle)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            #endif
            .sheet(isPresented: $isShowingOtherSources) {
                Text("TODO")
    //            DetailAlternativeSourcesSheet(
    //                title: "Other Sources",
    //                isLoading: isLoadingOtherSources,
    //                errorMessage: otherSourcesError,
    //                sources: otherSources,
    //                onRetry: { triggerOtherSourcesLookup() },
    //                destination: { EpisodeDetailTile(episode: $0) }
    //            )
            }
    }

    @ViewBuilder
    private func detailContent() -> some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                heroBackground(episode: episode, topInset: topInset)

                ScrollView {
                    VStack(spacing: 0) {
                        heroForeground(episode: episode, topInset: topInset)
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
                            primaryActions(episode: episode)

                            if let playError {
                                Text(playError)
                                    .foregroundStyle(.red)
                            }

                            overviewText(episode: episode)

                            if !scoreBadges(for: episode).isEmpty {
                                ratingSection(episode: episode)
                            }

                            episodeBrowser(season: episode.season)

                            if let cast = episode.info?.cast, !cast.isEmpty {
                                section("Cast", text: cast.joined())
                            }
                            
                            if let director = episode.info?.director, !director.isEmpty {
                                section("Director", text: director.joined())
                            }
                            
                            section("About", text: aboutText(for: episode))
                        }
                        .background(Color.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .coordinateSpace(name: "seriesDetailScroll")
                .scrollIndicators(.hidden)
                .onPreferenceChange(DetailHeroProgressPreferenceKey.self) { minY in
                    heroScrollOffset = minY
//                    heroCollapseProgress = heroProgress(for: minY)
                }

                DetailCollapsedHeaderBar(
                    title: displayTitle,
                    artworkURL: collapsedArtworkURL(for: episode),
                    titleArtworkURL: heroTitleArtworkURL(for: episode),
                    progress: heroCollapseProgress
                )
                .padding(.top, topInset + 8)
            }
            .background(Color.black.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private func episodeBrowser(season: Season) -> some View {
        VStack(alignment: .leading, spacing: DetailSpacing.md) {
            DetailSectionHeader(title: "Episodes")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DetailSpacing.xs) {
                    ForEach(episode.series.seasons, id: \.self) { season in
                        seasonButton(for: season, in: episode)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DetailSpacing.sm) {
                    ForEach(season.episodes) { episode in
                        if usesCompactDetailLayout {
                            episodeCard(episode: episode)
                                .id(episode.id)
                                .containerRelativeFrame(.horizontal, count: 7, span: 5, spacing: DetailSpacing.sm, alignment: .leading)
                        } else {
                            episodeCard(episode: episode)
                                .id(episode.id)
                                .frame(width: 288)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, DetailSpacing.xxs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $selectedEpisodeId)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func episodeCard(episode: Episode) -> some View {
        let isSelected = selectedEpisodeId == episode.id

        return VStack(alignment: .leading, spacing: DetailSpacing.sm) {
            Group {
                if let artworkURL = episode.info?.heroImageURL {
                    Text("TODO")
//                    AsyncImage(url: artworkURL) { phase in
//                        switch phase {
//                        case .success(let image):
//                            image
//                                .boundedCoverArtwork()
//                        default:
//                            placeholderArtwork(systemImage: "play.rectangle")
//                        }
//                    }
                } else {
                    placeholderArtwork(systemImage: "play.rectangle")
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: DetailSpacing.xs) {
//                Text(episodeBadgeText(for: episode))
//                    .font(.caption.weight(.semibold))
//                    .foregroundStyle(.white.opacity(0.62))

//                Text(episode.title)
//                    .font(.headline.weight(.semibold))
//                    .lineLimit(2)
//                    .foregroundStyle(.white)

//                HStack(spacing: DetailSpacing.xs) {
//                    if let runtimeText = episodeRuntimeText(for: episode, episode: episode) {
//                        Label(runtimeText, systemImage: "clock")
//                    }

//                    if let airDateText = episodeAirDateText(for: episode) {
//                        Label(airDateText, systemImage: "calendar")
//                    }
//                }
//                .font(.caption)
//                .foregroundStyle(.white.opacity(0.58))
//                .lineLimit(1)

//                episodeProgressSection(progress)

                HStack(spacing: DetailSpacing.xs) {
//                    playEpisodeButton(episode: episode, episode: episode)

                    DownloadStatusBadge()
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
            selectedEpisodeId = episode.id
        }
    }

    @ViewBuilder
    private func episodeProgressSection() -> some View {
        VStack(alignment: .leading, spacing: DetailSpacing.xxs + DetailSpacing.xxs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))

//                    if let progress {
//                        Capsule(style: .continuous)
//                            .fill(Color.white.opacity(0.84))
//                            .frame(width: max(geometry.size.width * progress.progressFraction, progress.progressFraction > 0 ? 6 : 0))
//                    }
                }
            }
            .frame(height: 4)

//            Text(progressStatusText(progress))
//                .font(.caption2.weight(.medium))
//                .foregroundStyle(.white.opacity(0.52))
        }
    }

    private func playEpisodeButton() -> some View {
        Button {
            player.load(episode, presentation: .inline)
        } label: {
            Label("Play", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DetailActionStyle(variant: .compactPrimary))
    }

    @ViewBuilder
    private func primaryActions(episode: Episode) -> some View {
        HStack(spacing: DetailSpacing.sm) {
            playButton(episode: episode)
            bookmarkButton
            DownloadStatusBadge(
//                selection: .series(episode),
//                showsTitle: false,
//                presentation: .detailAction(.icon)
            )
            otherSourcesButton
        }
    }
    
    private func playButton(episode: Episode) -> some View {
        Button {
            player.load(episode, presentation: .inline)
        } label: {
            Label(primaryActionTitle(for: episode), systemImage: "play.fill")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DetailActionStyle(variant: .primary))
//        .disabled(selectedEpisode(from: episode) == nil)
    }

    private var bookmarkButton: some View {
        Button {
            episode.isFavorite.toggle()
        } label: {
            Image(systemName: episode.isFavorite ? "heart.fill" : "heart")
        }
        .buttonStyle(DetailActionStyle(variant: .icon))
    }

    private var otherSourcesButton: some View {
        Button {
//            triggerOtherSourcesLookup()
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

    private var selectedSeasonDownloadBadge: some View {
        Text("TODO")
//        guard let seasonNumber = selectedSeasonNumber else { return nil }
//        return
//            DownloadStatusBadge(
//                selection: .season(seriesID: episode.id, seasonNumber: seasonNumber),
//                showsTitle: true,
//                presentation: .detailAction(.secondary)
//        )
    }

    @ViewBuilder
    private func seasonButton(for season: Season, in episode: Episode) -> some View {
        let isSelected = season.id == selectedSeasonId
        let episodesCount = season.episodes.count

        Button {
            selectedSeasonId = season.id
            selectedEpisodeId = episode.id
        } label: {
            VStack(alignment: .leading, spacing: DetailSpacing.xxxs) {
                Text(season.name)
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

    private func aboutText(for episode: Episode) -> String {
        var lines: [String] = []

        if let tmdb = episode.tmdbId {
            lines.append("TMDB: \(tmdb)")
        }
        
        lines.append("Seasons: \(episode.series.seasons.count)")
        lines.append("Episodes: \(episode.series.episodes.count)")

        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private func section(_ title: String?, text: String?) -> some View {
        if let title {
            DetailSectionHeader(title: title)
        } else {
            Text(text ?? String(localized: "Not available", comment: "Fallback when metadata is missing"))
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.white.opacity(0.9))
        }
    }
    
    private func primaryActionTitle(for episode: Episode) -> String {
        return String(
            localized: "Play E\(episode.episodeNumber)",
            locale: Locale.current,
            comment: "Primary action to play the selected episode"
        )
    }

    private func seasonTitle(in episode: Episode) -> String {
        return String(
            localized: "Season \(episode.season.seasonNumber)",
            locale: Locale.current,
            comment: "Season title in the episode browser"
        )
    }

    private func scoreBadges(for episode: Episode) -> [DetailScoreBadgeModel] {
        [
            DetailScoreSource.catalog.badgeModel(text: episode.rating?.formatted())
        ]
        .compactMap { $0 }
    }

    private var heroHeight: CGFloat {
        usesCompactDetailLayout ? 430 : 520
    }

    private func heroArtworkURL(for episode: Episode) -> URL? {
        episode.cover
    }

    private func collapsedArtworkURL(for episode: Episode) -> URL? {
        episode.cover
    }

    private func heroTitleArtworkURL(for episode: Episode) -> URL? {
       episode.cover
    }

    private func heroGenreText(for episode: Episode) -> String? {
        episode.info?.genre.joined()
    }

    private func heroYearText(for episode: Episode) -> String? {
        episode.info?.releaseDate?.formatted()
    }

    private func heroRuntimeText(for episode: Episode) -> String? {
        episode.info?.runtime?.formatted()
    }

    private func heroScoreText(for episode: Episode) -> String? {
        scoreBadges(for: episode).first?.value
    }

    private func overviewText(episode: Episode) -> some View {
        Text(episode.info?.plot ?? String(localized: "Not available.", comment: "Fallback when metadata is missing"))
            .font(.title3.weight(.regular))
            .lineSpacing(6)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ratingSection(episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: DetailSpacing.sm) {
            DetailSectionHeader(title: "Ratings")
            DetailScoreBadgeRow(badges: scoreBadges(for: episode))
        }
    }

    @ViewBuilder
    private func heroBackground(episode: Episode, topInset: CGFloat) -> some View {
        DetailHeroBackdrop(
            artworkURL: heroArtworkURL(for: episode),
            height: heroHeight,
            topInset: topInset,
            collapseProgress: heroCollapseProgress,
            scrollOffset: heroScrollOffset,
            artworkContentMode: usesCompactDetailLayout ? .fit : .fill
        )
    }

    private func heroForeground(episode: Episode, topInset: CGFloat) -> some View {
        VStack(spacing: DetailSpacing.md) {
            Spacer()

            VStack(spacing: DetailSpacing.md) {
                if let heroTitleArtworkURL = heroTitleArtworkURL(for: episode) {
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
                    .frame(maxWidth: usesCompactDetailLayout ? 220 : 280, maxHeight: usesCompactDetailLayout ? 84 : 96)
                    .frame(maxWidth: .infinity)
                    .shadow(color: Color.black.opacity(0.28), radius: 20, y: 10)
                }

                Text(displayTitle)
                    .font(.system(size: usesCompactDetailLayout ? 38 : 56, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.24), radius: 14, y: 8)

                heroMetaRow(episode: episode)

                if let heroGenreText = heroGenreText(for: episode) {
                    Text(heroGenreText)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .frame(maxWidth: usesCompactDetailLayout ? 320 : 760)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: heroHeight + topInset, alignment: .bottom)
        .padding(.horizontal, usesCompactDetailLayout ? 24 : 32)
        .padding(.top, topInset + 24)
        .padding(.bottom, DetailSpacing.lg)
        .opacity(1.0 - (Double(heroCollapseProgress) * 0.94))
        .offset(y: -(heroCollapseProgress * 18))
    }

    @ViewBuilder
    private func heroMetaRow(episode: Episode) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DetailSpacing.sm) {
                heroMetaItems(episode: episode)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: DetailSpacing.xs) {
                heroMetaItems(episode: episode)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func heroMetaItems(episode: Episode) -> some View {
        if let heroLanguageText {
            Text(heroLanguageText)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
        }
        if let heroScoreText = heroScoreText(for: episode) {
            DetailMetaPill(heroScoreText, systemImage: "star.fill")
        }
        if let heroYearText = heroYearText(for: episode) {
            Text(heroYearText)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)
        }
        if let heroRuntimeText = heroRuntimeText(for: episode) {
            Text(heroRuntimeText)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
        }
    }

    private func episodeCountText(_ count: Int) -> String {
        count == 1 ?
            String(localized: "1 episode", comment: "Single episode count")
            : String(localized: "\(count) episodes", locale: Locale.current, comment: "Plural episode count")
    }

    private func episodeRuntimeText() -> String? {
        episode.info?.runtime?.formatted()
    }

    private func progressStatusText() -> String {
        return "TODO"
//        guard let progress else {
//            return "Not started"
//        }
//
//        if progress.isCompleted {
//            return "Completed"
//        }
//
//        if let remaining = progress.remainingSeconds {
//            return "\(friendlyDurationText(seconds: remaining)) left"
//        }
//
//        return "\(Int(progress.progressFraction * 100))% watched"
    }
    
    private var usesCompactDetailLayout: Bool {
        horizontalSizeClass == .compact
    }

    private func startPlayback() {
        player.load(episode, presentation: .fullWindow)
    }

    private func loadOtherSources() async {
        print("TODO")
//        isLoadingOtherSources = true
//        otherSourcesError = nil
//
//        do {
//            otherSources = try await loadDetailAlternativeSources(
//                for: episode,
//                preferredTitle: normalizedText(episode?.info.name) ?? episode.name
//            )
//        } catch {
//            otherSources = []
//            otherSourcesError = error.localizedDescription
//        }
//
//        isLoadingOtherSources = false
    }
}

#Preview {
    NavigationStack {
//        EpisodeDetailTile(episode: .init(id: 10, name: "Example Series", containerExtension: "mp4", contentType: XtreamContentType.series.rawValue, cover: nil, tmdbId: nil, rating: nil))
    }
    .frame(width: 390, height: 844)
}
