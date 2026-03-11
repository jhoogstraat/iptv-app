//
//  VideoTile.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 03.09.25.
//

import SwiftUI

struct VideoTile: View {
    let video: Video

    private var selection: DownloadSelection? {
        switch video.xtreamContentType {
        case .vod:
            return .movie(video)
        case .series:
            return .series(video)
        case .live:
            return nil
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            artwork
            badgeRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.12))
        .clipShape(.rect(cornerRadius: 8))
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: URL(string: video.coverImageURL ?? "")) { phase in
            if let image = phase.image {
                image.boundedCoverArtwork()
            } else if phase.error != nil {
                VStack {
                    Spacer()
                    Text(video.name)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var badgeRow: some View {
        HStack {
            if let rating = video.formattedRating {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                    Text(rating)
                        .fontWeight(.semibold)
                }
                .font(.footnote)
                .padding(.horizontal, 2)
                .padding(4)
                .background(.thinMaterial)
                .clipShape(.rect(cornerRadius: 8))
            }
            Spacer()
            if let lang = video.language {
                Text(lang)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 2)
                    .padding(4)
                    .background(.thinMaterial)
                    .clipShape(.rect(cornerRadius: 8))
            }

            if let selection {
                DownloadStatusBadge(selection: selection)
            }
        }
        .padding(6)
    }
}

#Preview("Success") {
    VideoTile(video: .init(id: 0, name: "EN - test", containerExtension: "mkv", contentType: "movie", coverImageURL: "https://image.tmdb.org/t/p/w600_and_h900_bestv2/5aLm0igQgnBKikgn685U3n8658T.jpg", tmdbId: nil, rating: 5.6))
        .frame(width: 200, height: 300)
}

#Preview("Error") {
    VideoTile(video: .init(id: 0, name: "EN - Title of the movie", containerExtension: "mkv", contentType: "movie", coverImageURL: "error_url", tmdbId: nil, rating: 7.7))
        .frame(width: 200, height: 300)
}
