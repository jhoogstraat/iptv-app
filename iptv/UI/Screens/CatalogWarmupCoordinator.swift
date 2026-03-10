//
//  CatalogWarmupCoordinator.swift
//  iptv
//
//  Created by Codex on 10.03.26.
//

import Foundation
import OSLog

@MainActor
final class CatalogWarmupCoordinator {
    private var task: Task<Void, Never>?
    private var lastWarmupKey: String?

    func start(selectedTab: Tabs, providerRevision: Int, catalog: Catalog) {
        let warmupKey = "\(providerRevision)|\(selectedTab.id)"
        guard warmupKey != lastWarmupKey else { return }

        lastWarmupKey = warmupKey
        task?.cancel()

        task = Task(priority: .utility) { @MainActor in
            await self.run(selectedTab: selectedTab, catalog: catalog)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func run(selectedTab: Tabs, catalog: Catalog) async {
        guard catalog.hasProviderConfiguration else { return }

        let activityID = "catalog-warmup:\(selectedTab.id)"
        catalog.activityCenter.start(
            id: activityID,
            title: "Warming Library",
            detail: warmupTitle(for: selectedTab),
            source: "Startup"
        )

        do {
            try await catalog.activityCenter.waitIfResumed()
            try await catalog.getVodCategories(policy: .cachedThenRefresh)
            try await catalog.getSeriesCategories(policy: .cachedThenRefresh)

            switch selectedTab {
            case .home:
                let vodTargets = Array(catalog.vodCategories.prefix(6))
                let seriesTargets = Array(catalog.seriesCategories.prefix(4))
                let totalSteps = max(vodTargets.count + seriesTargets.count, 1)
                try await warm(
                    categories: vodTargets,
                    contentType: .vod,
                    catalog: catalog,
                    activityID: activityID,
                    completedSteps: 0,
                    totalSteps: totalSteps
                )
                try await warm(
                    categories: seriesTargets,
                    contentType: .series,
                    catalog: catalog,
                    activityID: activityID,
                    completedSteps: vodTargets.count,
                    totalSteps: totalSteps
                )
            case .movies:
                let targets = Array(catalog.vodCategories.prefix(8))
                try await warm(
                    categories: targets,
                    contentType: .vod,
                    catalog: catalog,
                    activityID: activityID,
                    completedSteps: 0,
                    totalSteps: max(targets.count, 1)
                )
            case .series:
                let targets = Array(catalog.seriesCategories.prefix(8))
                try await warm(
                    categories: targets,
                    contentType: .series,
                    catalog: catalog,
                    activityID: activityID,
                    completedSteps: 0,
                    totalSteps: max(targets.count, 1)
                )
            case .search:
                try await catalog.rebuildSearchIndexFromCachedMetadata()
            case .favorites, .downloads, .settings, .live:
                break
            }

            try await catalog.rebuildSearchIndexFromCachedMetadata()
            catalog.activityCenter.finish(id: activityID, detail: "Warmup complete")
        } catch is CancellationError {
            catalog.activityCenter.cancel(id: activityID)
            return
        } catch {
            catalog.activityCenter.fail(id: activityID, error: error)
            logger.debug("Catalog warmup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func warm(
        categories: [Category],
        contentType: XtreamContentType,
        catalog: Catalog,
        activityID: String,
        completedSteps: Int,
        totalSteps: Int
    ) async throws {
        guard !categories.isEmpty else { return }

        var imageURLs: [URL] = []
        imageURLs.reserveCapacity(categories.count * 6)

        for (offset, category) in categories.enumerated() {
            try await catalog.activityCenter.waitIfResumed()
            switch contentType {
            case .vod:
                try await catalog.getVodStreams(in: category, policy: .cachedThenRefresh)
                imageURLs.append(contentsOf: (catalog.vodCatalog[category] ?? []).prefix(12).compactMap(Self.imageURL(for:)))
            case .series:
                try await catalog.getSeriesStreams(in: category, policy: .cachedThenRefresh)
                imageURLs.append(contentsOf: (catalog.seriesCatalog[category] ?? []).prefix(12).compactMap(Self.imageURL(for:)))
            case .live:
                break
            }

            catalog.activityCenter.update(
                id: activityID,
                detail: "Warming \(category.name)",
                progress: (completedSteps + offset + 1, max(totalSteps, 1))
            )
        }

        try await catalog.activityCenter.waitIfResumed()
        await catalog.prefetchImages(urls: imageURLs)
    }

    private func warmupTitle(for selectedTab: Tabs) -> String {
        switch selectedTab {
        case .home:
            return "Preparing For You recommendations"
        case .movies:
            return "Preparing movie rails"
        case .series:
            return "Preparing series rails"
        case .search:
            return "Preparing search index"
        case .favorites, .downloads, .settings, .live:
            return "Refreshing cached content"
        }
    }

    private static func imageURL(for video: Video) -> URL? {
        guard let raw = video.coverImageURL else { return nil }
        return URL(string: raw)
    }
}
