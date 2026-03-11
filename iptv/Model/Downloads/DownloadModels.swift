//
//  DownloadModels.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation

enum PlaybackOrigin: String, Codable, Hashable, Sendable {
    case streaming
    case offline
}

struct PlaybackSource: Hashable, Sendable {
    let url: URL
    let origin: PlaybackOrigin
    let snapshotID: String?

    nonisolated static func streaming(_ url: URL) -> PlaybackSource {
        PlaybackSource(url: url, origin: .streaming, snapshotID: nil)
    }

    nonisolated static func offline(_ url: URL, snapshotID: String?) -> PlaybackSource {
        PlaybackSource(url: url, origin: .offline, snapshotID: snapshotID)
    }
}

struct DownloadScope: Codable, Hashable, Sendable {
    let profileID: String
    let providerFingerprint: String

    nonisolated var rawKey: String {
        "\(profileID)|\(providerFingerprint)"
    }

    nonisolated static func storageKey(for scope: DownloadScope) -> String {
        "\(scope.profileID)-\(scope.providerFingerprint.sha256Hex)"
    }
}

enum DownloadSelection: Hashable, Sendable {
    case movie(Video)
    case episode(seriesID: Int, episodeID: Int)
    case season(seriesID: Int, seasonNumber: Int)
    case series(Video)

    var contentSummary: String {
        switch self {
        case .movie(let video):
            return "\(video.contentType):\(video.id)"
        case .episode(let seriesID, let episodeID):
            return "series:\(seriesID):episode:\(episodeID)"
        case .season(let seriesID, let seasonNumber):
            return "series:\(seriesID):season:\(seasonNumber)"
        case .series(let video):
            return "\(video.contentType):\(video.id):series"
        }
    }
}

enum DownloadGroupKind: String, Codable, Hashable, Sendable {
    case movie
    case episode
    case season
    case series
}

enum DownloadStatus: String, Codable, Hashable, Sendable {
    case queued
    case preparing
    case downloading
    case paused
    case failedRestartable
    case failedTerminal
    case completed
    case removing
}

struct DownloadGroupRecord: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let scope: DownloadScope
    let kind: DownloadGroupKind
    let title: String
    let parentVideoID: Int
    let contentType: String
    let coverImageURL: String?
    var childAssetIDs: [String]
    var status: DownloadStatus
    var completedAssetCount: Int
    var totalAssetCount: Int
    var bytesWritten: Int64
    var expectedBytes: Int64?
    let createdAt: Date
    var updatedAt: Date

    nonisolated var progressFraction: Double {
        if let expectedBytes, expectedBytes > 0 {
            return min(max(Double(bytesWritten) / Double(expectedBytes), 0), 1)
        }
        guard totalAssetCount > 0 else { return 0 }
        return Double(completedAssetCount) / Double(totalAssetCount)
    }
}

struct DownloadAssetRecord: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let scope: DownloadScope
    let videoID: Int
    let contentType: String
    let title: String
    let coverImageURL: String?
    let containerExtension: String
    let seriesID: Int?
    let seasonNumber: Int?
    var remoteURL: URL
    var localURL: URL?
    var resumeDataURL: URL?
    var status: DownloadStatus
    var bytesWritten: Int64
    var expectedBytes: Int64?
    var attemptCount: Int
    var lastError: String?
    var metadataSnapshotID: String
    let createdAt: Date
    var updatedAt: Date

    nonisolated var scopedVideoKey: String {
        Self.scopedVideoKey(scope: scope, contentType: contentType, videoID: videoID)
    }

    nonisolated var progressFraction: Double {
        guard let expectedBytes, expectedBytes > 0 else { return status == .completed ? 1 : 0 }
        return min(max(Double(bytesWritten) / Double(expectedBytes), 0), 1)
    }

    func asVideo() -> Video {
        Video(
            id: videoID,
            name: title,
            containerExtension: containerExtension,
            contentType: contentType,
            coverImageURL: coverImageURL,
            tmdbId: nil,
            rating: nil
        )
    }

    nonisolated static func scopedVideoKey(scope: DownloadScope, contentType: String, videoID: Int) -> String {
        "\(scope.rawKey)|\(contentType)|\(videoID)"
    }
}

enum OfflineMetadataKind: String, Codable, Hashable, Sendable {
    case movie
    case series
}

struct OfflineMetadataSnapshot: Codable, Identifiable, Sendable {
    let id: String
    let scope: DownloadScope
    let kind: OfflineMetadataKind
    let videoID: Int
    let contentType: String
    let title: String
    let coverImageURL: String?
    let artworkByRemoteURL: [String: URL]
    let movieInfo: CachedVideoInfoDTO?
    let seriesInfo: XtreamSeries?
    let createdAt: Date
    var updatedAt: Date

    nonisolated func artworkURL(for candidates: [String?]) -> URL? {
        for candidate in candidates {
            guard let candidate, let url = artworkByRemoteURL[candidate] else { continue }
            return url
        }
        return nil
    }

    nonisolated var videoInfo: VideoInfo? {
        guard let movieInfo else { return nil }
        return VideoInfo(cached: movieInfo)
    }
}

struct DownloadPreparedMetadata: Sendable {
    let snapshotID: String
    let kind: OfflineMetadataKind
    let videoID: Int
    let contentType: String
    let title: String
    let coverImageURL: String?
    let artworkURLs: [URL]
    let movieInfo: CachedVideoInfoDTO?
    let seriesInfo: XtreamSeries?
}

enum DownloadBadgeState: Hashable, Sendable {
    case notDownloaded
    case queued
    case downloading(progress: Double?)
    case paused
    case failed
    case completed

    var symbolName: String {
        switch self {
        case .notDownloaded:
            return "arrow.down.circle"
        case .queued:
            return "clock.arrow.circlepath"
        case .downloading:
            return "arrow.down.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .notDownloaded:
            return "Download"
        case .queued:
            return "Queued"
        case .downloading:
            return "Downloading"
        case .paused:
            return "Paused"
        case .failed:
            return "Retry download"
        case .completed:
            return "Downloaded"
        }
    }
}

enum DownloadRuntimeError: LocalizedError {
    case missingProviderConfiguration
    case unsupportedContent
    case seriesMetadataUnavailable
    case episodeUnavailable
    case storageFailed(String)
    case assetNotFound
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingProviderConfiguration:
            return "Configure your provider before downloading content."
        case .unsupportedContent:
            return "This content cannot be downloaded."
        case .seriesMetadataUnavailable:
            return "Series details are unavailable, so the download could not be prepared."
        case .episodeUnavailable:
            return "The selected episode could not be found."
        case .storageFailed(let detail):
            return "Offline storage failed: \(detail)"
        case .assetNotFound:
            return "The requested download could not be found."
        case .downloadFailed(let detail):
            return detail
        }
    }
}
