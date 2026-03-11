//
//  SearchResultRowView.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import SwiftUI

struct SearchResultRowView: View {
    let item: SearchResultItem
    let isFavorite: Bool

    private var selection: DownloadSelection? {
        switch item.video.xtreamContentType {
        case .vod:
            return .movie(item.video)
        case .series:
            return .series(item.video)
        case .live:
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: item.video.coverImageURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .boundedCoverArtwork()
                case .empty:
                    ZStack {
                        Color.gray.opacity(0.25)
                        ProgressView()
                    }
                case .failure:
                    Color.gray.opacity(0.25)
                @unknown default:
                    Color.gray.opacity(0.25)
                }
            }
            .frame(width: 60, height: 90)
            .background(Color.secondary.opacity(0.12))
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.video.name)
                        .font(.headline)
                        .lineLimit(2)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                    }
                }

                HStack(spacing: 8) {
                    Text(item.scope.displayName)
                    if let rating = item.video.formattedRating {
                        Text("Rating \(rating)")
                    }
                    if let language = item.video.language {
                        Text(language)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let selection {
                DownloadStatusBadge(selection: selection)
            }
        }
    }
}
