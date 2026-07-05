//
//  VideoTileRow.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import SQLiteData

struct MovieTileRow: View {
    let category: Category

    @FetchAll private var media: [Media]

    init(category: Category) {
        self.category = category
        _media = FetchAll(Media.where { row in
            row.categoryID.eq(category.id)
        })
    }

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top) {
                    if media.isEmpty {
                        Text("No streams in this category")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(media) { item in
                            NavigationLink {
                                MediaDetailDestination(media: item, categoryTitle: category.title)
                            } label: {
                                VideoTile(media: item)
                                    .frame(width: 170, height: 9 / 6 * 170)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: 9 / 6 * 170 + 20)
        } header: {
            HStack {
                Text(category.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

#Preview {
    Text("MovieTileRow preview requires a synced category.")
}
