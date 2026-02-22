//
//  VideoTileRow.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI

struct VideoTileRow: View {
    let category: Category
    
    @Environment(Catalog.self) private var catalog
    @Environment(ProviderStore.self) private var providerStore
    
    @State private var isFetching: Bool = true
    @State private var error: Error?
    
    var body: some View {
        Section {
            Group {
                if let error = error {
                    VStack {
                        Text(error.localizedDescription)
                        Text("Error loading category")
                        Button("Retry") {
                            Task { await fetchVideos(force: true) }
                        }
                    }
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top) {
                            if isFetching {
                                ProgressView()
                            } else {
                                if let videos = catalog.vodCatalog[category], !videos.isEmpty {
                                    ForEach(videos) { video in
                                        NavigationLink {
                                            MovieDetailScreen(video: video)
                                        } label: {
                                            VideoTile(video: video)
                                                .frame(width: 170, height: 9/6 * 170)
                                        }
                                    }
                                } else {
                                    Text("No streams in this category")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.scrollIndicators(.never)
                }
            }.frame(height: 9/6 * 170 + 20)
        } header: {
            Button {
                Task { await fetchVideos(force: true) }
            } label: {
                Text(category.name)
            }
        }
        .task(id: providerStore.revision) {
            await fetchVideos()
        }
    }
    
    func fetchVideos(force: Bool = false) async {
        defer { isFetching = false }
        
        guard force || (catalog.vodCatalog[category] == nil && error == nil) else { return }
        
        isFetching = true
        error = nil
        
        do {
            try await catalog.getVodStreams(in: category, force: force)
        } catch {
            logger.error("Failed to load category \(category.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            self.error = error
        }
    }
}

#Preview(traits: .previewData, .fixedLayout(width: 1200, height: 700)) {
    ScrollView {
        LazyVStack(alignment: .leading) {
            VideoTileRow(category: Category(id: "1582", name: "name1"))
            VideoTileRow(category: Category(id: "857", name: "name2"))
            VideoTileRow(category: Category(id: "626", name: "name3"))
            VideoTileRow(category: Category(id: "643", name: "name4"))
            VideoTileRow(category: Category(id: "872", name: "name5"))
            VideoTileRow(category: Category(id: "644", name: "name6"))
        }
    }
}
