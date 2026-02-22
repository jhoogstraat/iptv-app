//
//  VideoTileRow.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import OSLog

struct VideoTileRow: View {
    let category: Category
    let contentType: XtreamContentType

    @Environment(Catalog.self) private var catalog
    @Environment(ProviderStore.self) private var providerStore

    @State private var isFetching: Bool = true
    @State private var error: Error?

    init(category: Category, contentType: XtreamContentType = .vod) {
        self.category = category
        self.contentType = contentType
    }

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
                                if let videos = videosInCategory, !videos.isEmpty {
                                    ForEach(videos) { video in
                                        NavigationLink {
                                            destination(for: video)
                                        } label: {
                                            VideoTile(video: video)
                                                .frame(width: 170, height: 9/6 * 170)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                } else {
                                    Text("No streams in this category")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
            .frame(height: 9/6 * 170 + 20)
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

    @ViewBuilder
    private func destination(for video: Video) -> some View {
        switch contentType {
        case .vod:
            MovieDetailScreen(video: video)
        case .series, .live:
            EpisodeDetailTile()
                .navigationTitle(video.name)
        }
    }

    private var videosInCategory: [Video]? {
        switch contentType {
        case .vod:
            catalog.vodCatalog[category]
        case .series:
            catalog.seriesCatalog[category]
        case .live:
            catalog.liveCatalog[category]
        }
    }

    func fetchVideos(force: Bool = false) async {
        defer { isFetching = false }

        guard force || (videosInCategory == nil && error == nil) else { return }

        isFetching = true
        error = nil

        do {
            switch contentType {
            case .vod:
                try await catalog.getVodStreams(in: category, force: force)
            case .series:
                try await catalog.getSeriesStreams(in: category, force: force)
            case .live:
                break
            }
        } catch {
            logger.error("Failed to load \(contentType.rawValue, privacy: .public) category \(category.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
