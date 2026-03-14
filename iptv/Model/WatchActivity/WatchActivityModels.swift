//
//  WatchActivityModels.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation

nonisolated struct WatchActivityInput: Hashable, Sendable {
    let videoID: Int
    let contentType: String
    let title: String
    let coverImageURL: String?
    let containerExtension: String
    let rating: Double?
}

nonisolated struct WatchProgressSnapshot: Hashable, Sendable {
    let lastPositionSeconds: Double
    let durationSeconds: Double?
    let progressFraction: Double
    let lastPlayedAt: Date
    let isCompleted: Bool

    var remainingSeconds: Double? {
        guard let durationSeconds else { return nil }
        return max(durationSeconds - lastPositionSeconds, 0)
    }
}

nonisolated struct WatchActivityRecord: Codable, Hashable, Sendable {
    let providerFingerprint: String
    let videoID: Int
    let contentType: String
    let title: String
    let coverImageURL: String?
    let containerExtension: String
    let rating: Double?
    let lastPositionSeconds: Double
    let durationSeconds: Double?
    let progressFraction: Double
    let lastPlayedAt: Date
    let isCompleted: Bool

    var key: String {
        Self.makeKey(providerFingerprint: providerFingerprint, contentType: contentType, videoID: videoID)
    }

    var progress: WatchProgressSnapshot {
        WatchProgressSnapshot(
            lastPositionSeconds: lastPositionSeconds,
            durationSeconds: durationSeconds,
            progressFraction: progressFraction,
            lastPlayedAt: lastPlayedAt,
            isCompleted: isCompleted
        )
    }

    static func makeKey(providerFingerprint: String, contentType: String, videoID: Int) -> String {
        "\(providerFingerprint)|\(contentType)|\(videoID)"
    }

    func asVideo() -> Video {
        Video(
            id: videoID,
            name: title,
            containerExtension: containerExtension,
            contentType: contentType,
            coverImageURL: coverImageURL,
            tmdbId: nil,
            rating: rating
        )
    }

    func updatingProgress(currentTime: Double, duration: Double?, now: Date) -> WatchActivityRecord {
        let normalizedDuration = duration.map { max($0, 0) }
        let normalizedPosition = max(currentTime, 0)
        let progressFraction: Double
        if let normalizedDuration, normalizedDuration > 0 {
            progressFraction = min(max(normalizedPosition / normalizedDuration, 0), 1)
        } else {
            progressFraction = 0
        }

        return WatchActivityRecord(
            providerFingerprint: providerFingerprint,
            videoID: videoID,
            contentType: contentType,
            title: title,
            coverImageURL: coverImageURL,
            containerExtension: containerExtension,
            rating: rating,
            lastPositionSeconds: normalizedPosition,
            durationSeconds: normalizedDuration,
            progressFraction: progressFraction,
            lastPlayedAt: now,
            isCompleted: progressFraction >= 0.98
        )
    }

    func markingCompleted(now: Date) -> WatchActivityRecord {
        WatchActivityRecord(
            providerFingerprint: providerFingerprint,
            videoID: videoID,
            contentType: contentType,
            title: title,
            coverImageURL: coverImageURL,
            containerExtension: containerExtension,
            rating: rating,
            lastPositionSeconds: durationSeconds ?? lastPositionSeconds,
            durationSeconds: durationSeconds,
            progressFraction: 1,
            lastPlayedAt: now,
            isCompleted: true
        )
    }

    static func from(input: WatchActivityInput, providerFingerprint: String, now: Date) -> WatchActivityRecord {
        WatchActivityRecord(
            providerFingerprint: providerFingerprint,
            videoID: input.videoID,
            contentType: input.contentType,
            title: input.title,
            coverImageURL: input.coverImageURL,
            containerExtension: input.containerExtension,
            rating: input.rating,
            lastPositionSeconds: 0,
            durationSeconds: nil,
            progressFraction: 0,
            lastPlayedAt: now,
            isCompleted: false
        )
    }
}
