//
//  DownloadStoreTests.swift
//  iptvTests
//
//  Created by Codex on 11.03.26.
//

import Foundation
import Testing
@testable import iptv

struct DownloadStoreTests {
    @Test
    func groupStatusTracksChildAssets() async {
        let store = makeStore()
        let scope = DownloadScope(profileID: "primary", providerFingerprint: "provider")

        let group = DownloadGroupRecord(
            id: "group-1",
            scope: scope,
            kind: .series,
            title: "Series",
            parentVideoID: 100,
            contentType: XtreamContentType.series.rawValue,
            coverImageURL: nil,
            childAssetIDs: ["asset-1", "asset-2"],
            status: .queued,
            completedAssetCount: 0,
            totalAssetCount: 2,
            bytesWritten: 0,
            expectedBytes: nil,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )

        await store.upsert(group: group, assets: [
            makeAsset(id: "asset-1", scope: scope, videoID: 1, status: .queued, snapshotID: "snap-1"),
            makeAsset(id: "asset-2", scope: scope, videoID: 2, status: .queued, snapshotID: "snap-2")
        ])

        await store.updateAssetProgress(id: "asset-1", bytesWritten: 50, expectedBytes: 100)
        let inProgress = await store.group(id: "group-1")
        #expect(inProgress?.status == .downloading)
        #expect(inProgress?.progressFraction == 0.25)

        await store.updateAsset(id: "asset-1", status: .completed, bytesWritten: 100, expectedBytes: 100)
        await store.updateAsset(id: "asset-2", status: .completed, bytesWritten: 100, expectedBytes: 100)

        let completed = await store.group(id: "group-1")
        #expect(completed?.status == .completed)
        #expect(completed?.completedAssetCount == 2)
        #expect(completed?.progressFraction == 1)
    }

    @Test
    func removeGroupOnlyDeletesSnapshotsWhenUnreferenced() async {
        let store = makeStore()
        let scope = DownloadScope(profileID: "primary", providerFingerprint: "provider")

        let firstGroup = DownloadGroupRecord(
            id: "group-1",
            scope: scope,
            kind: .movie,
            title: "One",
            parentVideoID: 1,
            contentType: XtreamContentType.vod.rawValue,
            coverImageURL: nil,
            childAssetIDs: ["asset-1"],
            status: .completed,
            completedAssetCount: 1,
            totalAssetCount: 1,
            bytesWritten: 100,
            expectedBytes: 100,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )

        let secondGroup = DownloadGroupRecord(
            id: "group-2",
            scope: scope,
            kind: .movie,
            title: "Two",
            parentVideoID: 2,
            contentType: XtreamContentType.vod.rawValue,
            coverImageURL: nil,
            childAssetIDs: ["asset-2"],
            status: .completed,
            completedAssetCount: 1,
            totalAssetCount: 1,
            bytesWritten: 100,
            expectedBytes: 100,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )

        await store.upsert(group: firstGroup, assets: [
            makeAsset(id: "asset-1", scope: scope, videoID: 1, status: .completed, snapshotID: "shared-snapshot")
        ])
        await store.upsert(group: secondGroup, assets: [
            makeAsset(id: "asset-2", scope: scope, videoID: 2, status: .completed, snapshotID: "shared-snapshot")
        ])

        let firstRemoval = await store.removeGroup(id: "group-1")
        #expect(firstRemoval.orphanedAssets.count == 1)
        #expect(firstRemoval.orphanedSnapshotIDs.isEmpty)

        let secondRemoval = await store.removeGroup(id: "group-2")
        #expect(secondRemoval.orphanedAssets.count == 1)
        #expect(secondRemoval.orphanedSnapshotIDs == Set(["shared-snapshot"]))
    }

    private func makeAsset(
        id: String,
        scope: DownloadScope,
        videoID: Int,
        status: DownloadStatus,
        snapshotID: String
    ) -> DownloadAssetRecord {
        DownloadAssetRecord(
            id: id,
            scope: scope,
            videoID: videoID,
            contentType: XtreamContentType.vod.rawValue,
            title: "Asset \(videoID)",
            coverImageURL: nil,
            containerExtension: "mp4",
            seriesID: nil,
            seasonNumber: nil,
            remoteURL: URL(string: "https://example.com/\(videoID).mp4")!,
            localURL: status == .completed ? URL(fileURLWithPath: "/tmp/\(videoID).mp4") : nil,
            resumeDataURL: nil,
            status: status,
            bytesWritten: status == .completed ? 100 : 0,
            expectedBytes: 100,
            attemptCount: 0,
            lastError: nil,
            metadataSnapshotID: snapshotID,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }

    private func makeStore() -> DownloadStore {
        DownloadStore(
            modelContainer: try! AppPersistence.makeModelContainer(isStoredInMemoryOnly: true)
        )
    }
}
