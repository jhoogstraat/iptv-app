//
//  MovieDetailScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 08.09.25.
//

import SwiftUI

struct MovieDetailScreen: View {
    let movie: Media

    @Environment(Player.self) private var player
    @State private var playError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DetailSpacing.md) {
                heroArtwork

                VStack(alignment: .leading, spacing: DetailSpacing.sm) {
                    Text(movie.title)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    metadataRow

                    HStack(spacing: DetailSpacing.sm) {
                        Button {
                            playError = nil
                            player.load(movie, presentation: .fullWindow)
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
        .navigationTitle(movie.title)
    }

    @ViewBuilder
    private var heroArtwork: some View {
        AsyncImage(url: movie.coverURL) { phase in
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
        .frame(height: 420)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top)
    }

    private var metadataRow: some View {
        HStack(spacing: DetailSpacing.xs) {
            Text("Movie")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if let rating = movie.rating {
                DetailMetaPill(rating.formatted(), systemImage: "star.fill")
            }
        }
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
                Image(systemName: "film")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }

    private var aboutText: String {
        var lines = ["Source ID: \(movie.sourceID)"]

        if let tmdbID = movie.tmdbID, !tmdbID.isEmpty {
            lines.append("TMDB: \(tmdbID)")
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
        Text("Movie detail preview requires synced media.")
    }
    .frame(width: 390, height: 844)
}
