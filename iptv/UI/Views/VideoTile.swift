//
//  VideoTile.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 03.09.25.
//

import SwiftUI

struct VideoTile: View {
    let media: Media
    
    var body: some View {
        ZStack(alignment: .top) {
            artwork
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.12))
        .clipShape(.rect(cornerRadius: 8))
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: media.coverURL) { phase in
            if let image = phase.image {
                image.boundedCoverArtwork()
            } else if phase.error != nil {
                VStack {
                    Spacer()
                    Text(media.title)
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
}

#Preview("Success") {
//    VideoTile(media: .init(id: 0, name: "EN - test", containerExtension: "mkv", contentType: "movie", cover: "https://image.tmdb.org/t/p/w600_and_h900_bestv2/5aLm0igQgnBKikgn685U3n8658T.jpg", tmdbId: nil, rating: 5.6))
//        .frame(width: 200, height: 300)
}

#Preview("Error") {
//    VideoTile(media: .init(id: 0, name: "EN - Title of the movie", containerExtension: "mkv", contentType: "movie", cover: "error_url", tmdbId: nil, rating: 7.7))
//        .frame(width: 200, height: 300)
}
