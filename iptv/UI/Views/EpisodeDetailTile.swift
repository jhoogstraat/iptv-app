//
//  EpisodeDetailTile.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 08.09.25.
//

import SwiftUI

struct EpisodeDetailTile: View {
    let series: Media
    let episode: Media

    @Environment(Player.self) private var player
    @State private var playError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DetailSpacing.md) {
                heroArtwork

                VStack(alignment: .leading, spacing: DetailSpacing.sm) {
                    Text(episode.title)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(series.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: DetailSpacing.sm) {
                        Button {
                            playError = nil
                            player.load(episode, presentation: .inline)
                            playError = player.errorMessage
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DetailActionStyle(variant: .primary))

                        DownloadStatusBadge()
                    }

                    if let playError {
                        Text(playError)
                            .font(.footnote)
                            .foregroundStyle(.red)
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
        AsyncImage(url: episode.coverURL ?? series.coverURL) { phase in
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

    private var aboutText: String {
        var lines = ["Source ID: \(episode.sourceID)"]

        if let tmdbID = episode.tmdbID, !tmdbID.isEmpty {
            lines.append("TMDB: \(tmdbID)")
        }

        if let rating = episode.rating {
            lines.append("Rating: \(rating.formatted())")
        }

        return lines.joined(separator: "\n")
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
