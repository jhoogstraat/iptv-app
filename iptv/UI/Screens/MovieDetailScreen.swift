//
//  MovieDetailScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 08.09.25.
//

import SwiftUI
import SQLiteData

struct MovieDetailScreen: View {
    @AppStorage(UserProfileStore.revisionKey) private var profileRevision = 0
    let movie: Media
    let categoryTitle: String?

    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
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
                        DetailEnrichmentStatus(
                            state: enrichmentState,
                            showsLoading: false,
                            retry: retryEnrichment
                        )
                        DetailMetadataGrid(
                            rows: metadataRows,
                            isLoading: enrichmentState.isAwaitingDetails
                        )
                    }
                }
            }
            .coordinateSpace(name: DetailScrollCoordinateSpace.name)
            .onPreferenceChange(DetailHeroProgressPreferenceKey.self) {
                heroCollapseProgress = $0
            }
            .onPreferenceChange(DetailHeroScrollOffsetPreferenceKey.self) {
                heroScrollOffset = $0
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(Color.black)
        .navigationTitle(currentMovie.title)
        .detailNavigationChrome(
            title: currentMovie.title,
            artworkURL: currentMovie.coverURL,
            progress: heroCollapseProgress
        )
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

                actionRow

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
    }

    private func metadataPills(stacked: Bool) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DetailSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DetailSpacing.xs))

        return layout {
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

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DetailSpacing.sm) {
                    actionButtons(fillWidth: false)
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: DetailSpacing.sm) {
                    actionButtons(fillWidth: true)
                }
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

    @ViewBuilder
    private func actionButtons(fillWidth: Bool) -> some View {
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
            .frame(maxWidth: fillWidth ? .infinity : nil)
        }
        .buttonStyle(DetailActionStyle(variant: .primary))

        Button(action: toggleFavorite) {
            Label(
                currentFavorite == nil ? "Add to Favorites" : "Remove from Favorites",
                systemImage: currentFavorite == nil ? "heart" : "heart.fill"
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: fillWidth ? .infinity : nil)
        }
        .buttonStyle(DetailActionStyle(variant: .secondary))
        .accessibilityHint("Updates the persisted favorite state for this provider.")

        DownloadStatusBadge(media: currentMovie, presentation: .detailAction(.secondary))
            .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)

        Menu {
            Button("Best Available", systemImage: "wand.and.stars") {
                player.load(currentMovie, presentation: .fullWindow)
            }
            Button("Provider Stream", systemImage: "network") {
                player.loadRemote(currentMovie)
            }
        } label: {
            Label("Sources", systemImage: "rectangle.stack.badge.play")
                .frame(maxWidth: fillWidth ? .infinity : nil)
        }
        .buttonStyle(DetailActionStyle(variant: .secondary))

        if let trailerURL = TrailerURLResolver.url(from: currentMovie.trailer) {
            Button {
                openURL(trailerURL)
            } label: {
                Label("Trailer", systemImage: "play.rectangle")
                    .frame(maxWidth: fillWidth ? .infinity : nil)
            }
            .buttonStyle(DetailActionStyle(variant: .secondary))
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

}

#Preview {
    NavigationStack {
        Text("Movie detail preview requires synced media.")
    }
    .frame(width: 390, height: 844)
}
