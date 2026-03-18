//
//  VideoTileRow.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import OSLog

struct MovieTileRow: View {
    let category: MovieCategory
    
    @Environment(SessionManager.self) private var sessionManager
    
    var body: some View {
        Section {
            Group {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top) {
                        if !category.media.isEmpty {
                            ForEach(category.movies) { movie in
                                NavigationLink {
                                    destination(for: movie)
                                } label: {
                                    VideoTile(media: movie)
                                        .frame(width: 170, height: 9/6 * 170)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            Text("No streams in this category")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
            .frame(height: 9/6 * 170 + 20)
        } header: {
            HStack {
                Text(category.name.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private func destination(for media: Media) -> some View {
        switch media.self {
            case is Movie:
                MovieDetailScreen(movie: media as! Movie)
                    .navigationTitle(media.name)
            case is Series:
                EpisodeDetailTile(series: media as! Series, episode: (media as! Series).episodes.first!)
                    .navigationTitle(media.name)
            default:
                ScopedPlaceholderView(
                    title: "Live Episodes Are Unavailable",
                    message: "Episode detail only applies to series content."
                )
                .navigationTitle(media.name)
        }
    }
}

#Preview(traits: .previewData, .fixedLayout(width: 1200, height: 700)) {
    ScrollView {
        LazyVStack(alignment: .leading) {
            MovieTileRow(category: MovieCategory(name: "name1"))
            MovieTileRow(category: MovieCategory(name: "name2"))
            MovieTileRow(category: MovieCategory(name: "name3"))
            MovieTileRow(category: MovieCategory(name: "name4"))
            MovieTileRow(category: MovieCategory(name: "name5"))
            MovieTileRow(category: MovieCategory(name: "name6"))
        }
    }
}
