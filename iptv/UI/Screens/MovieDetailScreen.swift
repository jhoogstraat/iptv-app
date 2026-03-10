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
    @Environment(Player.self) private var player
    @Environment(ProviderStore.self) private var providerStore
    @Environment(FavoritesStore.self) private var favoritesStore

    @State private var state: MovieDetailState = .fetching
    @State private var playError: String?
    @State private var isFavorite = false

    private var info: VideoInfo? {
        catalog.vodInfo[video]
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
                    .buttonStyle(.borderedProminent)
                }
                .padding()

            case .done:
                detailContent
            }
        }
        .navigationTitle(video.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadInfo(policy: .cachedThenRefresh)
            await loadFavoriteState()
        }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerArtwork

                VStack(alignment: .leading, spacing: 12) {
                    Text(video.name)
                        .font(.title.weight(.semibold))

                    Text(subtitleText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            startPlayback()
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            Task { await loadInfo(policy: .refreshNow) }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await toggleFavorite() }
                        } label: {
                            Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let playError {
                        Text(playError)
                            .foregroundStyle(.red)
                    }
                }

                section("Synopsis", text: info?.plot ?? "No synopsis available.")
                section("Cast", text: info?.cast ?? "No cast information available.")
                section("Director", text: info?.director ?? "No director information available.")
                section("About", text: aboutText)
            }
            .padding()
        }
    }

    private var headerArtwork: some View {
        Group {
            if let heroURL = info?.images.first ?? URL(string: video.coverImageURL ?? "") {
                AsyncImage(url: heroURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .boundedFillArtwork()
                    default:
                        Rectangle()
                            .fill(.gray.opacity(0.3))
                            .overlay {
                                ProgressView()
                            }
                    }
                }
            } else {
                Rectangle()
                    .fill(.gray.opacity(0.3))
            }
        }
        .frame(height: 260)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var subtitleText: String {
        [
            info?.genre,
            info?.releaseDate,
            info?.durationLabel,
            info?.ageRating
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }

    private var aboutText: String {
        var lines: [String] = []
        if let country = info?.country, !country.isEmpty {
            lines.append("Country: \(country)")
        }
        if let runtimeMinutes = info?.runtimeMinutes {
            lines.append("Runtime: \(runtimeMinutes) min")
        }
        if let rating = info?.rating {
            lines.append("Rating: \(rating.formatted(.number.precision(.fractionLength(1))))")
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(text.isEmpty ? "Not available." : text)
                .foregroundStyle(.secondary)
        }
    }

    private func loadInfo(policy: CatalogLoadPolicy = .cachedThenRefresh) async {
        guard policy == .refreshNow || info == nil else {
            state = .done
            return
        }

        do {
            state = .fetching
            try await catalog.getVodInfo(video, policy: policy)
            state = .done
        } catch {
            logger.error("Failed to load movie detail for \(video.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            state = .error(error)
        }
    }

    private func startPlayback() {
        do {
            let url = try catalog.resolveURL(for: video)
            playError = nil
            player.load(video, url, presentation: .fullWindow)
        } catch {
            playError = error.localizedDescription
            logger.error("Failed to resolve playback URL for \(video.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
    MovieDetailScreen(video: .init(id: 0, name: "EN - Title of the movie", containerExtension: "mkv", contentType: "movie", coverImageURL: "error_url", tmdbId: nil, rating: 7.7))
}
