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
                detail: itemCountText(activeAssets.count, singular: "download in progress", plural: "downloads in progress"),
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
                detail: itemCountText(pausedAssets.count, singular: "download paused", plural: "downloads paused"),
                source: "Downloads",
                progress: (completedAssets.count, max(assets.count, 1)),
                isPausable: false
            )
            return
        }

        if !failedAssets.isEmpty {
            let error = DownloadRuntimeError.downloadFailed("Some downloads need attention.")
            let detail = itemCountText(failedAssets.count, singular: "download needs attention", plural: "downloads need attention")
            activityCenter.start(
                id: activityID,
                title: "Downloads Need Attention",
                detail: detail,
                source: "Downloads",
                progress: (completedAssets.count, max(assets.count, 1)),
                isPausable: false
            )
            activityCenter.fail(id: activityID, error: error, detail: detail)
            return
        }

        if !completedAssets.isEmpty {
            let detail = itemCountText(completedAssets.count, singular: "download is ready offline", plural: "downloads are ready offline")
            activityCenter.start(
                id: activityID,
                title: "Downloads Complete",
                detail: detail,
                source: "Downloads",
                progress: (completedAssets.count, max(assets.count, 1)),
                isPausable: false
            )
            activityCenter.finish(id: activityID, detail: detail)
            return
        }

        if groups.isEmpty && assets.isEmpty {
            activityCenter.cancel(id: activityID)
        }
    }

    private func itemCountText(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }
}
