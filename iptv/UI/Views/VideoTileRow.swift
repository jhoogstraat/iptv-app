//
//  VideoTileRow.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import OSLog

struct VideoTileRow: View {
    private struct RowItem: Identifiable, Hashable {
        let id: Int
        let video: Video
    }

    let category: Category
    let contentType: XtreamContentType

    @Environment(Catalog.self) private var catalog
    @Environment(ProviderStore.self) private var providerStore

    @State private var isFetching: Bool = true
    @State private var error: Error?
    @State private var rowItems: [RowItem] = []

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
                            Task { await fetchVideos(policy: .forceRefresh) }
                        }
                    }
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top) {
                            if isFetching {
                                ProgressView()
                            } else {
                                if !rowItems.isEmpty {
                                    ForEach(rowItems) { item in
                                        NavigationLink {
                                            destination(for: item.video)
                                        } label: {
                                            VideoTile(video: item.video)
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
            HStack {
                Text(category.name.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .task(id: providerStore.revision) {
            await fetchVideos(policy: .readThrough)
        }
    }

    @ViewBuilder
    private func destination(for video: Video) -> some View {
        switch contentType {
        case .vod:
            MovieDetailScreen(video: video)
        case .series:
            EpisodeDetailTile(video: video)
                .navigationTitle(video.name)
        case .live:
            ScopedPlaceholderView(
                title: "Live Episodes Are Unavailable",
                message: "Episode detail only applies to series content."
            )
            .navigationTitle(video.name)
        }
    }

    private var cachedVideos: [Video]? {
        switch contentType {
        case .vod:
            catalog.cachedVideos(in: category, contentType: .vod)
        case .series:
            catalog.cachedVideos(in: category, contentType: .series)
        case .live:
            catalog.cachedVideos(in: category, contentType: .live)
        }
    }

    func fetchVideos(policy: CatalogLoadPolicy = .readThrough) async {
        defer { isFetching = false }

        guard policy == .forceRefresh || (cachedVideos == nil && error == nil) else {
            rowItems = (cachedVideos ?? []).map { RowItem(id: $0.id, video: $0) }
            return
        }

        isFetching = true
        error = nil

        do {
            switch contentType {
            case .vod:
                try await catalog.getVodStreams(in: category, policy: policy)
            case .series:
                try await catalog.getSeriesStreams(in: category, policy: policy)
            case .live:
                break
            }
            rowItems = (cachedVideos ?? []).map { RowItem(id: $0.id, video: $0) }
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
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
