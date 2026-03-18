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
    let movie: Movie

    @Environment(Player.self) private var player
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var state: MovieDetailState = .fetching
    @State private var playError: String?
    @State private var isFavorite = false
    @State private var offlineArtworkURL: URL?
    @State private var heroCollapseProgress: CGFloat = 0
    @State private var heroScrollOffset: CGFloat = 0
    @State private var isShowingOtherSources = false
    @State private var isLoadingOtherSources = false
    @State private var otherSources: [DetailAlternativeSource] = []
    @State private var otherSourcesError: String?
    
    private var displayTitle: String {
        movie.name
    }

    private var heroLanguageText: String? {
        movie.name
    }

    var body: some View {
        Group {
            switch state {
            case .fetching:
                ProgressView()

            case .error(let error):
                VStack(spacing: DetailSpacing.sm) {
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        print("TODO")
                    }
                    .buttonStyle(DetailActionStyle(variant: .primary))
                }
                .padding()

            case .done:
                detailContent
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
            Text("Not yet implemented")
//            DetailAlternativeSourcesSheet(
//                title: "Other Sources",
//                isLoading: isLoadingOtherSources,
//                errorMessage: otherSourcesError,
//                sources: otherSources,
//                onRetry: { triggerOtherSourcesLookup() },
//                destination: { MovieDetailScreen(movie: $0) }
//            )
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

//                            section("Cast", text: movie.cast ?? "No cast information available.")
                            section("Director", text: movie.director ?? "No director information available.")
                            section("About", text: aboutText)
                        }
                        .background(Color.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .coordinateSpace(name: "movieDetailScroll")
                .scrollIndicators(.hidden)
                .onPreferenceChange(DetailHeroProgressPreferenceKey.self) { minY in
                    heroScrollOffset = minY
                    heroCollapseProgress = heroProgress(for: minY)
                }

                DetailCollapsedHeaderBar(
                    title: displayTitle,
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
        HStack(spacing: DetailSpacing.sm) {
            playButton
            favoriteButton
            downloadButton
            otherSourcesButton
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
        DownloadStatusBadge()
    }

    private var favoriteButton: some View {
        Button {
            movie.isFavorite.toggle()
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

    private var scoreBadges: [DetailScoreBadgeModel] {
        [
            DetailScoreSource.catalog.badgeModel(value: movie.rating)
        ]
        .compactMap { $0 }
    }

    private var heroHeight: CGFloat {
        usesCompactDetailLayout ? 430 : 520
    }

    private var heroArtworkURL: URL? {
        offlineArtworkURL ?? movie.coverImageURL
    }

    private var collapsedArtworkURL: URL? {
        movie.coverImageURL ?? heroArtworkURL
    }

    private var heroTitleArtworkURL: URL? {
        guard let coverURL = movie.coverImageURL,
              coverURL != heroArtworkURL else {
            return nil
        }
        return coverURL
    }

    private var heroGenreText: String? {
        let genres = movie.genre?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let genres, !genres.isEmpty else { return nil }
        return genres.joined(separator: " / ")
    }

    private var heroYearText: String? {
        movie.releaseDate?.formatted(date: .abbreviated, time: .omitted)
    }

    private var heroRuntimeText: String? {
        movie.runtime?.formatted()
    }

    private var heroScoreText: String? {
        scoreBadges.first?.value
    }

    private var overviewText: some View {
        Text(movie.plot ?? "No synopsis available.")
            .font(.title3.weight(.regular))
            .lineSpacing(6)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.sm) {
            DetailSectionHeader(title: "Ratings")
            DetailScoreBadgeRow(badges: scoreBadges)
        }
    }

    private var aboutText: String {
        var lines: [String] = []
        
        if let country = movie.country, !country.isEmpty {
            lines.append("Country: \(country)")
        }
        
        if let runtime = movie.runtime {
            lines.append("Runtime: \(runtime.formatted()) min")
        }
        
        return lines.joined(separator: "\n")
    }

    private var usesCompactDetailLayout: Bool {
        horizontalSizeClass == .compact
    }

    @ViewBuilder
    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DetailSpacing.xs) {
            DetailSectionHeader(title: title)
            Text(text.isEmpty ? "Not available." : text)
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    @ViewBuilder
    private func heroBackground(topInset: CGFloat) -> some View {
        DetailHeroBackdrop(
            artworkURL: heroArtworkURL,
            height: heroHeight,
            topInset: topInset,
            collapseProgress: heroCollapseProgress,
            scrollOffset: heroScrollOffset,
            artworkContentMode: usesCompactDetailLayout ? .fit : .fill
        )
    }

    private func heroForeground(topInset: CGFloat) -> some View {
        VStack(spacing: DetailSpacing.md) {
            Spacer()

            VStack(spacing: DetailSpacing.md) {
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
                    .frame(maxWidth: usesCompactDetailLayout ? 220 : 280, maxHeight: usesCompactDetailLayout ? 84 : 96)
                    .frame(maxWidth: .infinity)
                    .shadow(color: Color.black.opacity(0.28), radius: 20, y: 10)
                }

                Text(displayTitle)
                    .font(.system(size: usesCompactDetailLayout ? 38 : 56, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.24), radius: 14, y: 8)

                heroMetaRow

                if let heroGenreText {
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
    private var heroMetaRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DetailSpacing.sm) {
                heroMetaItems
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: DetailSpacing.xs) {
                heroMetaItems
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var heroMetaItems: some View {
        if let heroLanguageText {
            Text(heroLanguageText)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
        }
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

    private func startPlayback() {
        Task {
            playError = nil
            player.load(movie, presentation: .fullWindow)
        }
    }

    private func triggerOtherSourcesLookup() {
        isShowingOtherSources = true
        guard !isLoadingOtherSources else { return }

        Task {
            await loadOtherSources()
        }
    }

    private func loadOtherSources() async {
        // TODO: Implement
//        isLoadingOtherSources = true
//        otherSourcesError = nil
//
//        do {
//            otherSources = try await loadDetailAlternativeSources(
//                for: video,
//                preferredTitle: video.name,
//                catalog: catalog
//            )
//        } catch {
//            otherSources = []
//            otherSourcesError = error.localizedDescription
//        }
//
//        isLoadingOtherSources = false
    }
}

#Preview(traits: .previewData) {
    NavigationStack {
//        MovieDetailScreen(video: .init(id: 0, name: "EN - Title of the movie", containerExtension: "mkv", contentType: "movie", coverImageURL: "error_url", tmdbId: nil, rating: 7.7))
    }
    .frame(width: 390, height: 844)
}
