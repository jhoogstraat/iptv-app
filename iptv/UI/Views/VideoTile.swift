//
//  VideoTile.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 03.09.25.
//

import SwiftUI

struct VideoTile: View {
    let video: Video

    var body: some View {
        AsyncImage(url: URL(string: video.coverImageURL ?? "")) { phase in
            if let image = phase.image {
                ZStack(alignment: .top) {
//                    RoundedRectangle(cornerRadius: 12)
//                        .fill()
                    image.resizable().scaledToFill()
                        .clipShape(.rect(cornerRadius: 8))
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
                    }.padding(6)
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.gray.opacity(0.1), lineWidth: 1.3, antialiased: true)
                }
            } else if phase.error != nil {
                VStack {
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
                    }
                    Spacer()
                    Text(video.name)
                    Spacer()
                }
                .padding(6)
                .background(Color.gray.brightness(-0.4).clipShape(.rect(cornerRadius: 8)))
            } else {
                Color.gray.brightness(-0.4)
            }
        }
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

