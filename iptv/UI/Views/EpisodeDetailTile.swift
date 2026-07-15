//
//  EpisodeDetailTile.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 08.09.25.
//

import SwiftUI
import SQLiteData

struct EpisodeDetailTile: View {
    @AppStorage(UserProfileStore.revisionKey) private var profileRevision = 0
    static let playbackPresentation: Presentation = .fullWindow
    let series: Media?
    let episode: Media

    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @FetchAll private var watchActivities: [WatchActivity]
    @FetchAll private var favorites: [Favorite]
    @State private var playError: String?
    @State private var favoriteError: String?

    init(series: Media?, episode: Media) {
        self.series = series
        self.episode = episode
        self._watchActivities = FetchAll(WatchActivity.where {
            $0.mediaType.eq(episode.type)
                .and($0.sourceID.eq(episode.sourceID))
        })
        self._favorites = FetchAll(Favorite.where {
            $0.mediaType.eq(episode.type)
                .and($0.sourceID.eq(episode.sourceID))
        })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DetailSpacing.md) {
                heroArtwork

                VStack(alignment: .leading, spacing: DetailSpacing.sm) {
                    Text(episode.title)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    if let series {
                        Text(series.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    if let activity = currentWatchActivity {
                        resumeProgress(for: activity)
                    }


                    HStack(spacing: DetailSpacing.sm) {
                        Button {
                            playError = nil
                            player.load(episode, presentation: Self.playbackPresentation)
                            playError = player.errorMessage
                        } label: {
                            Label(playButtonTitle, systemImage: playButtonSystemImage)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(DetailActionStyle(variant: .primary))
                        .accessibilityHint(playButtonHint)

                        Button {
                            do {
                                _ = try FavoriteStore.toggle(
                                    episode,
                                    providerID: session.providerID,
                                    categoryTitle: series?.title
                                )
                                favoriteError = nil
                            } catch {
                                favoriteError = error.localizedDescription
                            }
                        } label: {
                            Label(currentFavorite == nil ? "Add to Favorites" : "Remove from Favorites", systemImage: currentFavorite == nil ? "heart" : "heart.fill")
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(DetailActionStyle(variant: .icon))
                        .accessibilityHint("Updates the persisted favorite state for this provider.")

                        DownloadStatusBadge()
                    }

                    if let favoriteError {
                        Text("Couldn’t update Favorites: \(favoriteError)")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Favorites update failed. \(favoriteError)")
                    }

                    if let playError {
                        Text(playError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Playback failed. \(playError)")
                    }

                    section("About", text: aboutText)
                }
                .padding(.horizontal)
                .padding(.bottom, DetailSpacing.lg)
            }
        }
        .navigationTitle(episode.title)
    }

    @ViewBuilder
    private var heroArtwork: some View {
        AsyncImage(url: episode.coverURL ?? series?.coverURL) { phase in
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
        .frame(height: 360)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top)
    }

    private var placeholderArtwork: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.secondary.opacity(0.30), Color.secondary.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "play.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }

    private var currentWatchActivity: WatchActivity? {
        watchActivities.first {
            $0.profileID == session.activeProfileID
                && $0.providerID == session.providerID
                && $0.mediaType == episode.type
                && $0.sourceID == episode.sourceID
        }
    }

    private var currentFavorite: Favorite? {
        favorites.first {
            $0.profileID == session.activeProfileID
                && $0.providerID == session.providerID
                && $0.mediaType == episode.type
                && $0.sourceID == episode.sourceID
        }
    }

    private var shouldResumeEpisode: Bool {
        currentWatchActivity?.isResumeEligible == true
    }

    private var playButtonTitle: String {
        if currentWatchActivity?.completed == true {
            return "Replay"
        }
        guard shouldResumeEpisode, let activity = currentWatchActivity else { return "Play" }
        return "Resume \(Self.formatDuration(activity.currentTime))"
    }

    private var playButtonSystemImage: String {
        if currentWatchActivity?.completed == true {
            return "arrow.counterclockwise"
        }
        return shouldResumeEpisode ? "play.circle.fill" : "play.fill"
    }

    private var playButtonHint: String {
        if currentWatchActivity?.completed == true {
            return "Starts this episode again from the beginning in the full-window player."
        }
        if shouldResumeEpisode {
            return "Continues this episode in the full-window player."
        }
        return "Starts this episode in the full-window player."
    }

    @ViewBuilder
    private func resumeProgress(for activity: WatchActivity) -> some View {
        if activity.isResumeEligible {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: activity.progressFraction)

                Text(resumeSummaryText(for: activity))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(resumeSummaryText(for: activity))
        } else if activity.completed {
            Text("Watched. Play starts from the beginning.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
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

    private var aboutText: String {
        var lines: [String] = []

        if let synopsis = episode.synopsis?.trimmingCharacters(in: .whitespacesAndNewlines), !synopsis.isEmpty {
            lines.append(synopsis)
        } else {
            lines.append("No episode synopsis is available in the synced library record.")
        }

        if let seasonNumber = episode.seasonNumber, let episodeNumber = episode.episodeNumber {
            lines.append("Episode: S\(seasonNumber) E\(episodeNumber)")
        }

        if let releaseDate = episode.releaseDate {
            lines.append("Released: \(releaseDate.formatted(date: .abbreviated, time: .omitted))")
        }

        if let runtimeSeconds = episode.runtimeSeconds, runtimeSeconds > 0 {
            lines.append("Runtime: \(runtimeSeconds / 60)m")
        }

        if let rating = episode.rating {
            lines.append("Rating: \(rating.formatted(.number.precision(.fractionLength(1))))")
        }

        if let tmdbID = episode.tmdbID, !tmdbID.isEmpty {
            lines.append("TMDB: \(tmdbID)")
        }

        lines.append("Source ID: \(episode.sourceID)")
        return lines.joined(separator: "\n\n")
    }

    @ViewBuilder
    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DetailSpacing.xs) {
            DetailSectionHeader(title: title)
            Text(text.isEmpty ? "Not available." : text)
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        Text("Episode detail preview requires synced media.")
    }
    .frame(width: 390, height: 844)
}
