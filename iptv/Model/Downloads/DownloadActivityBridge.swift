//
//  DownloadActivityBridge.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation

@MainActor
final class DownloadActivityBridge {
    private let activityCenter: BackgroundActivityCenter
    private let activityID = "downloads"

    init(activityCenter: BackgroundActivityCenter) {
        self.activityCenter = activityCenter
    }

    func sync(groups: [DownloadGroupRecord], assets: [DownloadAssetRecord]) {
        let activeAssets = assets.filter { $0.status == .downloading || $0.status == .preparing || $0.status == .queued }
        let pausedAssets = assets.filter { $0.status == .paused }
        let failedAssets = assets.filter { $0.status == .failedRestartable || $0.status == .failedTerminal }
        let completedAssets = assets.filter { $0.status == .completed }

        let expectedBytes = activeAssets.compactMap(\.expectedBytes).reduce(0, +)
        let writtenBytes = activeAssets.reduce(0) { $0 + $1.bytesWritten }

        if !activeAssets.isEmpty {
            activityCenter.start(
                id: activityID,
                title: "Downloading Content",
                detail: "\(activeAssets.count) item(s) in progress",
                source: "Downloads",
                progress: (Int(writtenBytes), max(Int(expectedBytes), 1)),
                isPausable: false
            )
            return
        }

        if !pausedAssets.isEmpty {
            activityCenter.start(
                id: activityID,
                title: "Downloads Paused",
                detail: "\(pausedAssets.count) item(s) paused",
                source: "Downloads",
                progress: (completedAssets.count, max(assets.count, 1)),
                isPausable: false
            )
            return
        }

        if !failedAssets.isEmpty {
            let error = DownloadRuntimeError.downloadFailed("Some downloads need attention.")
            activityCenter.start(
                id: activityID,
                title: "Downloads Need Attention",
                detail: "\(failedAssets.count) item(s) failed",
                source: "Downloads",
                progress: (completedAssets.count, max(assets.count, 1)),
                isPausable: false
            )
            activityCenter.fail(id: activityID, error: error, detail: "\(failedAssets.count) item(s) failed")
            return
        }

        if !completedAssets.isEmpty {
            activityCenter.start(
                id: activityID,
                title: "Downloads Complete",
                detail: "\(completedAssets.count) item(s) ready offline",
                source: "Downloads",
                progress: (completedAssets.count, max(assets.count, 1)),
                isPausable: false
            )
            activityCenter.finish(id: activityID, detail: "\(completedAssets.count) item(s) ready offline")
            return
        }

        if groups.isEmpty && assets.isEmpty {
            activityCenter.cancel(id: activityID)
        }
    }
}
