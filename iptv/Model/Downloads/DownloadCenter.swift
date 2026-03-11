//
//  DownloadCenter.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation
import Observation

private final class DownloadCenterRefreshRelay: @unchecked Sendable {
    weak var center: DownloadCenter?

    func onRecordsChanged() async {
        guard let center else { return }
        await center.refresh()
    }
}

@MainActor
@Observable
final class DownloadCenter {
    private let providerStore: ProviderStore
    private let catalog: Catalog
    private let store: DownloadStore
    private let assetStore: OfflineAssetStore
    private let metadataStore: OfflineMetadataStore
    private let planner: DownloadPlanner
    private let scheduler: DownloadScheduler
    private let playbackSourceResolver: PlaybackSourceResolver
    private let activityBridge: DownloadActivityBridge
    private let refreshRelay = DownloadCenterRefreshRelay()

    private var snapshotCache: [String: OfflineMetadataSnapshot] = [:]

    private(set) var groups: [DownloadGroupRecord] = []
    private(set) var assets: [DownloadAssetRecord] = []
    private(set) var revision = 0
    private(set) var lastErrorMessage: String?

    init(
        providerStore: ProviderStore,
        catalog: Catalog,
        backgroundActivityCenter: BackgroundActivityCenter,
        store: DownloadStore? = nil,
        assetStore: OfflineAssetStore? = nil,
        metadataStore: OfflineMetadataStore? = nil,
        sessionClient: DownloadSessionClient? = nil
    ) {
        self.providerStore = providerStore
        self.catalog = catalog
        self.store = store ?? DownloadStore()
        self.assetStore = assetStore ?? OfflineAssetStore()
        self.metadataStore = metadataStore ?? OfflineMetadataStore()
        self.activityBridge = DownloadActivityBridge(activityCenter: backgroundActivityCenter)

        self.playbackSourceResolver = PlaybackSourceResolver(
            store: self.store,
            scopeProvider: { [weak providerStore] in
                guard let providerStore,
                      let config = try? providerStore.configuration() else { return nil }
                return DownloadScope(profileID: "primary", providerFingerprint: ProviderCacheFingerprint.make(from: config))
            }
        )

        self.planner = DownloadPlanner(
            catalog: catalog,
            store: self.store,
            metadataStore: self.metadataStore,
            scopeProvider: { [weak providerStore] in
                guard let providerStore,
                      let config = try? providerStore.configuration() else { return nil }
                return DownloadScope(profileID: "primary", providerFingerprint: ProviderCacheFingerprint.make(from: config))
            }
        )

        self.scheduler = DownloadScheduler(
            store: self.store,
            assetStore: self.assetStore,
            sessionClient: sessionClient ?? DownloadSessionClient(),
            onRecordsChanged: { [refreshRelay] in
                await refreshRelay.onRecordsChanged()
            }
        )
        refreshRelay.center = self

        Task {
            await refresh()
            await scheduler.start()
        }
    }

    var visibleGroups: [DownloadGroupRecord] {
        if let scope = currentScope() {
            return groups.filter { $0.scope == scope }
        }
        return groups
    }

    var visibleAssets: [DownloadAssetRecord] {
        if let scope = currentScope() {
            return assets.filter { $0.scope == scope }
        }
        return assets
    }

    func observe(scope: DownloadScope? = nil) -> [DownloadGroupRecord] {
        let resolvedScope = scope ?? currentScope()
        guard let resolvedScope else { return groups }
        return groups.filter { $0.scope == resolvedScope }
    }

    func enqueue(_ selection: DownloadSelection) async {
        do {
            let plan = try await planner.plan(selection)
            await store.upsert(group: plan.group, assets: plan.assets)
            lastErrorMessage = nil
            await refresh()
            await scheduler.wake()
        } catch {
            lastErrorMessage = error.localizedDescription
            await refresh()
        }
    }

    func pause(groupOrAssetID: String) async {
        await scheduler.pause(ids: [groupOrAssetID])
        await refresh()
    }

    func resume(groupOrAssetID: String) async {
        await scheduler.resume(ids: [groupOrAssetID])
        await refresh()
    }

    func retry(groupOrAssetID: String) async {
        await scheduler.retry(ids: [groupOrAssetID])
        await refresh()
    }

    func remove(groupOrAssetID: String) async {
        await scheduler.cancel(ids: [groupOrAssetID])

        let removal: DownloadRemovalPlan
        if await store.group(id: groupOrAssetID) != nil {
            removal = await store.removeGroup(id: groupOrAssetID)
        } else {
            removal = DownloadRemovalPlan(removedGroup: nil, orphanedAssets: [], orphanedSnapshotIDs: [])
        }

        for asset in removal.orphanedAssets {
            try? await assetStore.removeFiles(for: asset)
        }
        for snapshotID in removal.orphanedSnapshotIDs {
            await metadataStore.removeSnapshot(id: snapshotID)
            snapshotCache[snapshotID] = nil
        }

        await refresh()
        await scheduler.wake()
    }

    func removeAll(scope: DownloadScope? = nil) async {
        let resolvedScope = scope ?? currentScope()
        let groupIDs = observe(scope: resolvedScope).map(\.id)
        await scheduler.cancel(ids: groupIDs)
        let removal = await store.removeAll(scope: resolvedScope)

        for asset in removal.orphanedAssets {
            try? await assetStore.removeFiles(for: asset)
        }
        for snapshotID in removal.orphanedSnapshotIDs {
            await metadataStore.removeSnapshot(id: snapshotID)
            snapshotCache[snapshotID] = nil
        }

        await refresh()
    }

    func playbackSource(for video: Video) async throws -> PlaybackSource {
        try await playbackSourceResolver.resolve(
            video: video,
            streamingURL: try catalog.resolveURL(for: video)
        )
    }

    func playbackSourceForGroup(_ group: DownloadGroupRecord) async -> PlaybackSource? {
        guard let firstAssetID = group.childAssetIDs.first,
              let asset = await store.asset(id: firstAssetID),
              let localURL = asset.localURL else {
            return nil
        }
        return .offline(localURL, snapshotID: asset.metadataSnapshotID)
    }

    func badgeState(for video: Video) -> DownloadBadgeState {
        switch video.xtreamContentType {
        case .vod:
            return badgeState(for: .movie(video))
        case .series:
            return badgeState(for: .series(video))
        case .live:
            return .notDownloaded
        }
    }

    func badgeState(for selection: DownloadSelection) -> DownloadBadgeState {
        let relevantGroup = matchingGroup(for: selection)
        let relevantAssets = relevantGroup?.childAssetIDs.compactMap { id in assets.first(where: { $0.id == id }) } ?? matchingAssets(for: selection)

        let status = relevantGroup?.status ?? relevantAssets.first?.status
        let progress = relevantGroup?.progressFraction ?? relevantAssets.first?.progressFraction

        switch status {
        case .completed:
            return .completed
        case .failedRestartable, .failedTerminal:
            return .failed
        case .paused:
            return .paused
        case .downloading:
            return .downloading(progress: progress)
        case .queued, .preparing, .removing:
            return .queued
        case nil:
            return .notDownloaded
        }
    }

    func groupID(for selection: DownloadSelection) -> String? {
        matchingGroup(for: selection)?.id
    }

    func offlineMovieInfo(for video: Video) async -> VideoInfo? {
        await offlineSnapshot(for: video)?.videoInfo
    }

    func offlineSeriesInfo(for video: Video) async -> XtreamSeries? {
        await offlineSnapshot(for: video)?.seriesInfo
    }

    func offlineArtworkURL(for video: Video, candidates: [String?]) async -> URL? {
        await offlineSnapshot(for: video)?.artworkURL(for: candidates)
    }

    func displayVideo(for group: DownloadGroupRecord) async -> Video {
        switch group.kind {
        case .movie:
            if let assetID = group.childAssetIDs.first,
               let asset = assets.first(where: { $0.id == assetID }) {
                return asset.asVideo()
            }
        case .series, .season, .episode:
            if let snapshot = await snapshotForGroup(group) {
                return Video(
                    id: group.parentVideoID,
                    name: snapshot.title,
                    containerExtension: "mp4",
                    contentType: group.contentType,
                    coverImageURL: group.coverImageURL ?? snapshot.coverImageURL,
                    tmdbId: nil,
                    rating: nil
                )
            }
        }

        return Video(
            id: group.parentVideoID,
            name: group.title,
            containerExtension: "mp4",
            contentType: group.contentType,
            coverImageURL: group.coverImageURL,
            tmdbId: nil,
            rating: nil
        )
    }

    func refresh() async {
        let view = await store.view()
        groups = view.groups
        assets = view.assets
        revision += 1
        activityBridge.sync(groups: groups, assets: assets)
    }

    private func currentScope() -> DownloadScope? {
        guard let config = try? providerStore.configuration() else { return nil }
        return DownloadScope(profileID: "primary", providerFingerprint: ProviderCacheFingerprint.make(from: config))
    }

    private func matchingGroup(for selection: DownloadSelection) -> DownloadGroupRecord? {
        let scope = currentScope()
        return groups.first { group in
            if let scope, group.scope != scope {
                return false
            }

            switch selection {
            case .movie(let video):
                return group.kind == .movie && group.parentVideoID == video.id && group.contentType == video.contentType
            case .series(let video):
                return group.kind == .series && group.parentVideoID == video.id
            case .season(let seriesID, let seasonNumber):
                return group.kind == .season &&
                    group.parentVideoID == seriesID &&
                    group.id.contains("-\(seasonNumber)")
            case .episode(let seriesID, let episodeID):
                return group.kind == .episode &&
                    group.parentVideoID == seriesID &&
                    group.id.hasSuffix("-\(episodeID)")
            }
        }
    }

    private func matchingAssets(for selection: DownloadSelection) -> [DownloadAssetRecord] {
        let scope = currentScope()
        return assets.filter { asset in
            if let scope, asset.scope != scope {
                return false
            }

            switch selection {
            case .movie(let video):
                return asset.videoID == video.id && asset.contentType == video.contentType
            case .series(let video):
                return asset.seriesID == video.id
            case .season(let seriesID, let seasonNumber):
                return asset.seriesID == seriesID && asset.seasonNumber == seasonNumber
            case .episode(_, let episodeID):
                return asset.videoID == episodeID
            }
        }
    }

    private func offlineSnapshot(for video: Video) async -> OfflineMetadataSnapshot? {
        if let scope = currentScope(),
           let asset = await store.completedAsset(videoID: video.id, contentType: video.contentType, preferredScope: scope) {
            return await cachedSnapshot(id: asset.metadataSnapshotID)
        }

        if let asset = await store.completedAsset(videoID: video.id, contentType: video.contentType, preferredScope: nil) {
            return await cachedSnapshot(id: asset.metadataSnapshotID)
        }

        if video.xtreamContentType == .series,
           let group = matchingGroup(for: .series(video)) {
            return await snapshotForGroup(group)
        }

        return nil
    }

    private func snapshotForGroup(_ group: DownloadGroupRecord) async -> OfflineMetadataSnapshot? {
        for assetID in group.childAssetIDs {
            guard let asset = assets.first(where: { $0.id == assetID }) else { continue }
            if let snapshot = await cachedSnapshot(id: asset.metadataSnapshotID) {
                return snapshot
            }
        }
        return nil
    }

    private func cachedSnapshot(id: String) async -> OfflineMetadataSnapshot? {
        if let snapshot = snapshotCache[id] {
            return snapshot
        }
        let snapshot = await metadataStore.snapshot(id: id)
        snapshotCache[id] = snapshot
        return snapshot
    }
}
