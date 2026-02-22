//
//  StreamPrefetchCoordinator.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation
import OSLog

@MainActor
final class StreamPrefetchCoordinator {
    private let windowSize: Int
    private let maxConcurrent: Int
    private var task: Task<Void, Never>?

    init(windowSize: Int = 8, maxConcurrent: Int = 3) {
        self.windowSize = windowSize
        self.maxConcurrent = maxConcurrent
    }

    func start(categories: [Category], contentType: XtreamContentType, catalog: Catalog) {
        stop()

        guard contentType != .live else { return }
        let targets = Array(categories.prefix(windowSize))
        guard !targets.isEmpty else { return }

        task = Task(priority: .utility) { @MainActor in
            var index = 0
            while index < targets.count && !Task.isCancelled {
                let endIndex = min(index + maxConcurrent, targets.count)
                let batch = Array(targets[index..<endIndex])

                let batchTasks = batch.map { category in
                    Task(priority: .utility) { @MainActor in
                        try await self.prefetch(category: category, contentType: contentType, catalog: catalog)
                    }
                }

                for batchTask in batchTasks {
                    do {
                        try await batchTask.value
                    } catch is CancellationError {
                        return
                    } catch {
                        logger.debug("Prefetch failed for \(contentType.rawValue, privacy: .public) category: \(error.localizedDescription, privacy: .public)")
                    }
                }

                index = endIndex
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func prefetch(category: Category, contentType: XtreamContentType, catalog: Catalog) async throws {
        switch contentType {
        case .vod:
            try await catalog.getVodStreams(in: category)
        case .series:
            try await catalog.getSeriesStreams(in: category)
        case .live:
            return
        }

        let videos: [Video]
        switch contentType {
        case .vod:
            videos = catalog.vodCatalog[category] ?? []
        case .series:
            videos = catalog.seriesCatalog[category] ?? []
        case .live:
            videos = []
        }

        let imageURLs = videos.compactMap { video -> URL? in
            guard let raw = video.coverImageURL, let url = URL(string: raw) else { return nil }
            return url
        }
        await catalog.prefetchImages(urls: imageURLs)
    }
}
