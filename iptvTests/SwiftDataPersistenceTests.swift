//
//  SwiftDataPersistenceTests.swift
//  iptvTests
//
//  Created by Codex on 14.03.26.
//

import Foundation
import SwiftData
import Testing
@testable import iptv

@MainActor
struct SwiftDataPersistenceTests {
    @Test
    func favoritesAndWatchActivityPersistAcrossStoreInstances() async throws {
        let container = try makeInMemoryContainer()
        let favorites = SwiftDataFavoritesStore(modelContainer: container, now: { Date(timeIntervalSince1970: 10) })
        let watchActivity = SwiftDataWatchActivityStore(modelContainer: container, now: { Date(timeIntervalSince1970: 20) })

        let favoriteInput = FavoriteInput(
            videoID: 42,
            contentType: XtreamContentType.vod.rawValue,
            title: "Demo",
            coverImageURL: "https://example.com/poster.jpg",
            containerExtension: "mp4",
            rating: 8.2
        )
        await favorites.add(input: favoriteInput, providerFingerprint: "provider-a")

        let watchInput = WatchActivityInput(
            videoID: 42,
            contentType: XtreamContentType.vod.rawValue,
            title: "Demo",
            coverImageURL: "https://example.com/poster.jpg",
            containerExtension: "mp4",
            rating: 8.2
        )
        await watchActivity.recordProgress(
            input: watchInput,
            providerFingerprint: "provider-a",
            currentTime: 90,
            duration: 300
        )

        let reloadedFavorites = SwiftDataFavoritesStore(modelContainer: container)
        let favoriteRecords = await reloadedFavorites.loadAll()
        #expect(favoriteRecords.count == 1)
        #expect(favoriteRecords.first?.providerFingerprint == "provider-a")
        #expect(favoriteRecords.first?.videoID == 42)

        let reloadedWatchActivity = SwiftDataWatchActivityStore(modelContainer: container)
        let watchRecords = await reloadedWatchActivity.loadAll()
        #expect(watchRecords.count == 1)
        #expect(watchRecords.first?.providerFingerprint == "provider-a")
        #expect(watchRecords.first?.progressFraction == 0.3)

        await reloadedFavorites.clear(for: "provider-a")
        await reloadedWatchActivity.clear(for: "provider-a")

        let clearedFavorites = await favorites.loadAll()
        let clearedWatchActivity = await watchActivity.loadAll()
        #expect(clearedFavorites.isEmpty)
        #expect(clearedWatchActivity.isEmpty)
    }

    @Test
    func searchIndexPersistsAcrossInstances() async throws {
        let container = try makeInMemoryContainer()
        let store = SearchIndexStore(modelContainer: container)

        await store.replaceCategory(
            videos: [makeSearchSnapshot(id: 7, name: "SwiftData Movie", contentType: XtreamContentType.vod.rawValue)],
            contentType: .vod,
            categoryID: "featured",
            categoryName: "Featured",
            providerFingerprint: "provider-a"
        )

        let reloaded = SearchIndexStore(modelContainer: container)
        let results = await reloaded.query(
            SearchQuery(text: "swiftdata", scope: .movies, filters: .default, sort: .title),
            providerFingerprint: "provider-a"
        )

        #expect(results.count == 1)
        #expect(results.first?.video.id == 7)

        await reloaded.removeCategory(
            contentType: .vod,
            categoryID: "featured",
            providerFingerprint: "provider-a"
        )
        let afterRemoval = await store.query(
            SearchQuery(text: "", scope: .movies, filters: .default, sort: .title),
            providerFingerprint: "provider-a"
        )
        #expect(afterRemoval.isEmpty)
    }

    @Test
    func downloadsAndOfflineMetadataPersistAcrossInstances() async throws {
        let container = try makeInMemoryContainer()
        let downloadStore = DownloadStore(modelContainer: container)
        let scope = DownloadScope(profileID: "primary", providerFingerprint: "provider-a")
        let group = DownloadGroupRecord(
            id: "group-1",
            scope: scope,
            kind: .movie,
            title: "Offline Demo",
            parentVideoID: 501,
            contentType: XtreamContentType.vod.rawValue,
            coverImageURL: "https://example.com/poster.jpg",
            childAssetIDs: ["asset-1"],
            status: .queued,
            completedAssetCount: 0,
            totalAssetCount: 1,
            bytesWritten: 0,
            expectedBytes: 100,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
        let asset = DownloadAssetRecord(
            id: "asset-1",
            scope: scope,
            videoID: 501,
            contentType: XtreamContentType.vod.rawValue,
            title: "Offline Demo",
            coverImageURL: "https://example.com/poster.jpg",
            containerExtension: "mp4",
            seriesID: nil,
            seasonNumber: nil,
            remoteURL: URL(string: "https://example.com/movie.mp4")!,
            localURL: URL(fileURLWithPath: "/tmp/offline-demo.mp4"),
            resumeDataURL: nil,
            status: .completed,
            bytesWritten: 100,
            expectedBytes: 100,
            attemptCount: 0,
            lastError: nil,
            metadataSnapshotID: "snapshot-1",
            createdAt: .distantPast,
            updatedAt: .distantPast
        )

        await downloadStore.upsert(group: group, assets: [asset])

        let reloadedDownloadStore = DownloadStore(modelContainer: container)
        let reloadedGroup = await reloadedDownloadStore.group(id: "group-1")
        let reloadedAsset = await reloadedDownloadStore.asset(id: "asset-1")
        #expect(reloadedGroup?.status == .completed)
        #expect(reloadedAsset?.metadataSnapshotID == "snapshot-1")

        let metadataRootDirectory = temporaryDirectory()
        let metadataStore = OfflineMetadataStore(
            rootDirectoryURL: metadataRootDirectory,
            modelContainer: container,
            session: .shared
        )

        let snapshot = try await metadataStore.store(
            prepared: DownloadPreparedMetadata(
                snapshotID: "snapshot-1",
                kind: .movie,
                videoID: 501,
                contentType: XtreamContentType.vod.rawValue,
                title: "Offline Demo",
                coverImageURL: "https://example.com/poster.jpg",
                artworkURLs: [],
                movieInfo: CachedVideoInfoDTO(
                    images: [],
                    plot: "Stored in SwiftData",
                    cast: "Demo Cast",
                    director: "Demo Director",
                    genre: "Action",
                    releaseDate: "2026-01-01",
                    durationLabel: "120m",
                    runtimeMinutes: 120,
                    ageRating: "PG-13",
                    country: "US",
                    rating: 8.2,
                    streamBitrate: 4_000,
                    audioDescription: "Stereo",
                    videoResolution: "1080p",
                    videoFrameRate: 24
                ),
                seriesInfo: nil
            ),
            scope: scope
        )
        #expect(snapshot.movieInfo?.plot == "Stored in SwiftData")

        let reloadedMetadataStore = OfflineMetadataStore(
            rootDirectoryURL: metadataRootDirectory,
            modelContainer: container,
            session: .shared
        )
        let restoredSnapshot = await reloadedMetadataStore.snapshot(id: "snapshot-1")
        #expect(restoredSnapshot?.title == "Offline Demo")
        #expect(restoredSnapshot?.movieInfo?.director == "Demo Director")

        await reloadedMetadataStore.removeSnapshot(id: "snapshot-1")
        let removedSnapshot = await metadataStore.snapshot(id: "snapshot-1")
        #expect(removedSnapshot == nil)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try AppPersistence.makeModelContainer(isStoredInMemoryOnly: true)
    }

    private func makeSearchSnapshot(
        id: Int,
        name: String,
        contentType: String
    ) -> SearchVideoSnapshot {
        SearchVideoSnapshot(
            id: id,
            name: name,
            containerExtension: "mp4",
            contentType: contentType,
            coverImageURL: "https://example.com/\(id).jpg",
            rating: 7.5,
            addedAtRaw: "2026-03-14",
            language: "en"
        )
    }

    private func temporaryDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "swiftdata-persistence-tests")
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
