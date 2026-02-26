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
    @Environment(Player.self) private var player

    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var seriesInfo: XtreamSeries?
    @State private var playError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let loadError {
                VStack(spacing: 12) {
                    Text(loadError.localizedDescription)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadSeriesInfo(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let seriesInfo {
                detailContent(seriesInfo: seriesInfo)
            } else {
                Text("Series details are unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(video.name)
        .task {
            await loadSeriesInfo()
        }
    }

    @ViewBuilder
    private func detailContent(seriesInfo: XtreamSeries) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(seriesInfo.info.plot)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let playError {
                    Text(playError)
                        .foregroundStyle(.red)
                }

                ForEach(sortedSeasonKeys(from: seriesInfo), id: \.self) { seasonKey in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Season \(seasonKey)")
                            .font(.headline)

                        ForEach(episodes(in: seasonKey, from: seriesInfo), id: \.id) { episode in
                            Button {
                                startPlayback(episode: episode, seriesInfo: seriesInfo)
                            } label: {
                                HStack(spacing: 10) {
                                    Text("E\(episode.episodeNum)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 34, alignment: .leading)
                                    Text(episode.title)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "play.fill")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding()
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

    private func episodeVideos(from seriesInfo: XtreamSeries) -> [Video] {
        sortedSeasonKeys(from: seriesInfo)
            .flatMap { season in episodes(in: season, from: seriesInfo) }
            .map(Video.init(from:))
    }

    private func startPlayback(episode: XtreamEpisode, seriesInfo: XtreamSeries) {
        let candidates = episodeVideos(from: seriesInfo)
        let episodeID = Int(episode.id) ?? episode.info.id
        guard let selected = candidates.first(where: { $0.id == episodeID }) else { return }

        do {
            player.configureEpisodeSwitcher(episodes: candidates) { episodeVideo in
                try catalog.resolveURL(for: episodeVideo)
            }

            let url = try catalog.resolveURL(for: selected)
            playError = nil
            player.load(selected, url, presentation: .fullWindow)
        } catch {
            playError = error.localizedDescription
            logger.error("Failed to start episode playback for \(episode.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadSeriesInfo(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            seriesInfo = try await catalog.getSeriesInfo(video, force: force)
            loadError = nil
        } catch {
            loadError = error
            logger.error("Failed to load series detail for \(video.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

#Preview {
    EpisodeDetailTile(video: .init(id: 10, name: "Example Series", containerExtension: "mp4", contentType: XtreamContentType.series.rawValue, coverImageURL: nil, tmdbId: nil, rating: nil))
}
