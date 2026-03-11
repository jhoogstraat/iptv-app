//
//  DownloadPlanner.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation

struct DownloadEnqueuePlan: Sendable {
    let group: DownloadGroupRecord
    let assets: [DownloadAssetRecord]
}

actor DownloadPlanner {
    private let catalog: Catalog
    private let store: DownloadStore
    private let metadataStore: OfflineMetadataStore
    private let scopeProvider: @MainActor @Sendable () throws -> DownloadScope?
    private let now: @Sendable () -> Date

    init(
        catalog: Catalog,
        store: DownloadStore,
        metadataStore: OfflineMetadataStore,
        scopeProvider: @escaping @MainActor @Sendable () throws -> DownloadScope?,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.catalog = catalog
        self.store = store
        self.metadataStore = metadataStore
        self.scopeProvider = scopeProvider
        self.now = now
    }

    func plan(_ selection: DownloadSelection) async throws -> DownloadEnqueuePlan {
        guard let scope = try await MainActor.run(body: { try scopeProvider() }) else {
            throw DownloadRuntimeError.missingProviderConfiguration
        }

        switch selection {
        case .movie(let video):
            return try await planMovie(video, scope: scope)
        case .series(let video):
            return try await planSeries(video, scope: scope)
        case .season(let seriesID, let seasonNumber):
            return try await planSeason(seriesID: seriesID, seasonNumber: seasonNumber, scope: scope)
        case .episode(let seriesID, let episodeID):
            return try await planEpisode(seriesID: seriesID, episodeID: episodeID, scope: scope)
        }
    }

    private func planMovie(_ video: Video, scope: DownloadScope) async throws -> DownloadEnqueuePlan {
        guard video.xtreamContentType == .vod else {
            throw DownloadRuntimeError.unsupportedContent
        }

        let metadata = try await catalog.prepareDownloadMetadata(for: video)
        _ = try await metadataStore.store(prepared: metadata, scope: scope)

        let assetID = DownloadIdentifiers.assetID(scope: scope, contentType: video.contentType, videoID: video.id)
        let groupID = DownloadIdentifiers.groupID(scope: scope, kind: .movie, parentVideoID: video.id)
        let remoteURL = try await catalog.resolveURL(for: video)
        let asset = await plannedAsset(
            existing: await store.asset(scope: scope, contentType: video.contentType, videoID: video.id),
            id: assetID,
            scope: scope,
            video: video,
            seriesID: nil,
            seasonNumber: nil,
            remoteURL: remoteURL,
            metadataSnapshotID: metadata.snapshotID
        )

        let group = await plannedGroup(
            id: groupID,
            scope: scope,
            kind: .movie,
            title: video.name,
            parentVideoID: video.id,
            contentType: video.contentType,
            coverImageURL: video.coverImageURL,
            childAssetIDs: [asset.id]
        )

        return DownloadEnqueuePlan(group: group, assets: [asset])
    }

    private func planSeries(_ video: Video, scope: DownloadScope) async throws -> DownloadEnqueuePlan {
        guard video.xtreamContentType == .series else {
            throw DownloadRuntimeError.unsupportedContent
        }

        let metadata = try await catalog.prepareDownloadMetadata(for: video)
        _ = try await metadataStore.store(prepared: metadata, scope: scope)

        guard let seriesInfo = metadata.seriesInfo else {
            throw DownloadRuntimeError.seriesMetadataUnavailable
        }

        let episodeVideos = seriesInfo.downloadEpisodeVideos()
        let assets = try await episodeVideos.asyncMap { episodeVideo in
            let assetID = DownloadIdentifiers.assetID(scope: scope, contentType: episodeVideo.contentType, videoID: episodeVideo.id)
            let remoteURL = try await catalog.resolveEpisodeDownloadURL(
                seriesID: video.id,
                episodeVideoID: episodeVideo.id,
                containerExtension: episodeVideo.containerExtension,
                directSource: seriesInfo.directSource(forEpisodeVideoID: episodeVideo.id)
            )
            return await plannedAsset(
                existing: await store.asset(scope: scope, contentType: episodeVideo.contentType, videoID: episodeVideo.id),
                id: assetID,
                scope: scope,
                video: episodeVideo,
                seriesID: video.id,
                seasonNumber: seriesInfo.seasonNumber(forEpisodeVideoID: episodeVideo.id),
                remoteURL: remoteURL,
                metadataSnapshotID: metadata.snapshotID
            )
        }

        let group = await plannedGroup(
            id: DownloadIdentifiers.groupID(scope: scope, kind: .series, parentVideoID: video.id),
            scope: scope,
            kind: .series,
            title: metadata.title,
            parentVideoID: video.id,
            contentType: video.contentType,
            coverImageURL: video.coverImageURL,
            childAssetIDs: assets.map(\.id)
        )

        return DownloadEnqueuePlan(group: group, assets: assets)
    }

    private func planSeason(seriesID: Int, seasonNumber: Int, scope: DownloadScope) async throws -> DownloadEnqueuePlan {
        let seriesVideo = Video(
            id: seriesID,
            name: "Series \(seriesID)",
            containerExtension: "mp4",
            contentType: XtreamContentType.series.rawValue,
            coverImageURL: nil,
            tmdbId: nil,
            rating: nil
        )
        let metadata = try await catalog.prepareDownloadMetadata(for: seriesVideo)
        _ = try await metadataStore.store(prepared: metadata, scope: scope)

        guard let seriesInfo = metadata.seriesInfo else {
            throw DownloadRuntimeError.seriesMetadataUnavailable
        }

        let seasonEpisodes = seriesInfo.downloadEpisodes(inSeasonNumber: seasonNumber)
        guard !seasonEpisodes.isEmpty else {
            throw DownloadRuntimeError.episodeUnavailable
        }

        let assets = try await seasonEpisodes.asyncMap { episode in
            let episodeVideo = Video(from: episode)
            let assetID = DownloadIdentifiers.assetID(scope: scope, contentType: episodeVideo.contentType, videoID: episodeVideo.id)
            let remoteURL = try await catalog.resolveEpisodeDownloadURL(
                seriesID: seriesID,
                episodeVideoID: episodeVideo.id,
                containerExtension: episodeVideo.containerExtension,
                directSource: episode.directSource
            )
            return await plannedAsset(
                existing: await store.asset(scope: scope, contentType: episodeVideo.contentType, videoID: episodeVideo.id),
                id: assetID,
                scope: scope,
                video: episodeVideo,
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                remoteURL: remoteURL,
                metadataSnapshotID: metadata.snapshotID
            )
        }

        let seasonTitle = seriesInfo.seasonTitle(for: seasonNumber)
        let group = await plannedGroup(
            id: DownloadIdentifiers.groupID(scope: scope, kind: .season, parentVideoID: seriesID, seasonNumber: seasonNumber),
            scope: scope,
            kind: .season,
            title: seasonTitle,
            parentVideoID: seriesID,
            contentType: XtreamContentType.series.rawValue,
            coverImageURL: metadata.coverImageURL,
            childAssetIDs: assets.map(\.id)
        )

        return DownloadEnqueuePlan(group: group, assets: assets)
    }

    private func planEpisode(seriesID: Int, episodeID: Int, scope: DownloadScope) async throws -> DownloadEnqueuePlan {
        let seriesVideo = Video(
            id: seriesID,
            name: "Series \(seriesID)",
            containerExtension: "mp4",
            contentType: XtreamContentType.series.rawValue,
            coverImageURL: nil,
            tmdbId: nil,
            rating: nil
        )
        let metadata = try await catalog.prepareDownloadMetadata(for: seriesVideo)
        _ = try await metadataStore.store(prepared: metadata, scope: scope)

        guard let seriesInfo = metadata.seriesInfo else {
            throw DownloadRuntimeError.seriesMetadataUnavailable
        }

        guard let episode = seriesInfo.downloadEpisode(videoID: episodeID) else {
            throw DownloadRuntimeError.episodeUnavailable
        }

        let episodeVideo = Video(from: episode)
        let assetID = DownloadIdentifiers.assetID(scope: scope, contentType: episodeVideo.contentType, videoID: episodeVideo.id)
        let remoteURL = try await catalog.resolveEpisodeDownloadURL(
            seriesID: seriesID,
            episodeVideoID: episodeVideo.id,
            containerExtension: episodeVideo.containerExtension,
            directSource: episode.directSource
        )
        let asset = await plannedAsset(
            existing: await store.asset(scope: scope, contentType: episodeVideo.contentType, videoID: episodeVideo.id),
            id: assetID,
            scope: scope,
            video: episodeVideo,
            seriesID: seriesID,
            seasonNumber: episode.season,
            remoteURL: remoteURL,
            metadataSnapshotID: metadata.snapshotID
        )

        let group = await plannedGroup(
            id: DownloadIdentifiers.groupID(scope: scope, kind: .episode, parentVideoID: seriesID, seasonNumber: episode.season, episodeID: episodeVideo.id),
            scope: scope,
            kind: .episode,
            title: episode.title,
            parentVideoID: seriesID,
            contentType: XtreamContentType.series.rawValue,
            coverImageURL: episode.info.movieImage.isEmpty ? metadata.coverImageURL : episode.info.movieImage,
            childAssetIDs: [asset.id]
        )

        return DownloadEnqueuePlan(group: group, assets: [asset])
    }

    private func plannedGroup(
        id: String,
        scope: DownloadScope,
        kind: DownloadGroupKind,
        title: String,
        parentVideoID: Int,
        contentType: String,
        coverImageURL: String?,
        childAssetIDs: [String]
    ) async -> DownloadGroupRecord {
        if let existing = await store.group(id: id) {
            var updated = existing
            updated.childAssetIDs = Array(Set(existing.childAssetIDs + childAssetIDs)).sorted()
            updated.updatedAt = now()
            return updated
        }

        let timestamp = now()
        return DownloadGroupRecord(
            id: id,
            scope: scope,
            kind: kind,
            title: title,
            parentVideoID: parentVideoID,
            contentType: contentType,
            coverImageURL: coverImageURL,
            childAssetIDs: childAssetIDs,
            status: .queued,
            completedAssetCount: 0,
            totalAssetCount: childAssetIDs.count,
            bytesWritten: 0,
            expectedBytes: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private func plannedAsset(
        existing: DownloadAssetRecord?,
        id: String,
        scope: DownloadScope,
        video: Video,
        seriesID: Int?,
        seasonNumber: Int?,
        remoteURL: URL,
        metadataSnapshotID: String
    ) async -> DownloadAssetRecord {
        let timestamp = now()

        if var existing {
            existing.remoteURL = remoteURL
            existing.metadataSnapshotID = metadataSnapshotID
            existing.updatedAt = timestamp
            existing.lastError = nil
            if existing.status != .completed && existing.status != .downloading && existing.status != .preparing {
                existing.status = .queued
            }
            return existing
        }

        return DownloadAssetRecord(
            id: id,
            scope: scope,
            videoID: video.id,
            contentType: video.contentType,
            title: video.name,
            coverImageURL: video.coverImageURL,
            containerExtension: video.containerExtension,
            seriesID: seriesID,
            seasonNumber: seasonNumber,
            remoteURL: remoteURL,
            localURL: nil,
            resumeDataURL: nil,
            status: .queued,
            bytesWritten: 0,
            expectedBytes: nil,
            attemptCount: 0,
            lastError: nil,
            metadataSnapshotID: metadataSnapshotID,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            try Task.checkCancellation()
            values.append(try await transform(element))
        }
        return values
    }
}

private extension XtreamSeries {
    nonisolated func downloadEpisode(videoID: Int) -> XtreamEpisode? {
        episodes.values
            .flatMap { $0 }
            .first { (Int($0.id) ?? $0.info.id) == videoID }
    }

    nonisolated func downloadEpisodes(inSeasonNumber seasonNumber: Int) -> [XtreamEpisode] {
        (episodes[String(seasonNumber)] ?? [])
            .sorted { $0.episodeNum < $1.episodeNum }
    }

    nonisolated func downloadEpisodeVideos() -> [Video] {
        episodes.keys
            .sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
            .flatMap { key in
                (episodes[key] ?? [])
                    .sorted { $0.episodeNum < $1.episodeNum }
                    .map(Video.init(from:))
            }
    }

    nonisolated func seasonTitle(for seasonNumber: Int) -> String {
        seasons.first(where: { $0.seasonNumber == seasonNumber })?.name.nonEmpty ?? "Season \(seasonNumber)"
    }

    nonisolated func seasonNumber(forEpisodeVideoID videoID: Int) -> Int? {
        downloadEpisode(videoID: videoID)?.season
    }

    nonisolated func directSource(forEpisodeVideoID videoID: Int) -> String {
        downloadEpisode(videoID: videoID)?.directSource ?? ""
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
