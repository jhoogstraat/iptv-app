//
//  SearchResultRowView.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import SwiftUI

struct SearchResultRowView: View {
    let row: SearchResultRowState

    private var selection: DownloadSelection? {
        switch row.summary.xtreamContentType {
        case .vod:
            return .movie(row.summary.asVideo())
        case .series:
            return .series(row.summary.asVideo())
        case .live:
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: row.summary.artworkURL) { phase in
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
                    Text(row.summary.name)
                        .font(.headline)
                        .lineLimit(2)
                    if row.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                    }
                }

                HStack(spacing: 8) {
                    Text(row.scope.displayName)
                    if let rating = row.summary.displayRating {
                        Text("Rating \(rating)")
                    }
                    if let language = row.summary.language {
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
