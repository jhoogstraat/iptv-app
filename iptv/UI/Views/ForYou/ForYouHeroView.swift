//
//  ForYouHeroView.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import SwiftUI

struct ForYouHeroView: View {
    let item: ForYouItem
    let onPlay: () -> Void
    let onDetails: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: item.artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .boundedFillArtwork()
                case .failure:
                    Rectangle()
                        .fill(.gray.opacity(0.35))
                case .empty:
                    Rectangle()
                        .fill(.gray.opacity(0.35))
                        .overlay { ProgressView() }
                @unknown default:
                    Rectangle()
                        .fill(.gray.opacity(0.35))
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Tonight's Pick")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(item.video.name)
                    .font(.title.weight(.bold))
                    .lineLimit(2)

                metadataLine

                HStack(spacing: 12) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onDetails) {
                        Label("Details", systemImage: "info.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding(18)
        }
        .frame(height: 320)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var metadataLine: some View {
        HStack(spacing: 8) {
            switch item.badge {
            case .rating(let value):
                Label(value, systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
            case .language(let value):
                Text(value.uppercased())
            case .isNew:
                Text("NEW")
            case .series:
                Text("SERIES")
            case .none:
                EmptyView()
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}
