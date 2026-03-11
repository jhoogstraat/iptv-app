//
//  PlaybackSourceResolver.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation

actor PlaybackSourceResolver {
    private let store: DownloadStore
    private let scopeProvider: @MainActor @Sendable () -> DownloadScope?

    init(
        store: DownloadStore,
        scopeProvider: @escaping @MainActor @Sendable () -> DownloadScope?
    ) {
        self.store = store
        self.scopeProvider = scopeProvider
    }

    func resolve(video: Video, streamingURL: @autoclosure () throws -> URL) async throws -> PlaybackSource {
        let preferredScope = await MainActor.run { scopeProvider() }
        if let localAsset = await store.completedAsset(
            videoID: video.id,
            contentType: video.contentType,
            preferredScope: preferredScope
        ), let localURL = localAsset.localURL, FileManager.default.fileExists(atPath: localURL.path()) {
            return .offline(localURL, snapshotID: localAsset.metadataSnapshotID)
        }

        return .streaming(try streamingURL())
    }
}

