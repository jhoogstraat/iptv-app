//
//  SearchIndexStoreTests.swift
//  iptvTests
//
//  Created by Codex on 24.02.26.
//

import Foundation
import Testing
@testable import iptv

@MainActor
struct SearchIndexStoreTests {
    @Test
    func providerIsolation() async {
        let store = SearchIndexStore()

        await store.upsert(
            videos: [makeSnapshot(id: 1, name: "Alpha Movie", contentType: "vod")],
            contentType: .vod,
            categoryID: "10",
            categoryName: "Action",
            providerFingerprint: "provider-a"
        )

        await store.upsert(
            videos: [makeSnapshot(id: 2, name: "Beta Movie", contentType: "vod")],
            contentType: .vod,
            categoryID: "10",
            categoryName: "Action",
            providerFingerprint: "provider-b"
        )

        let query = SearchQuery(text: "movie", scope: .all, filters: .default, sort: .relevance)
        let providerAResults = await store.query(query, providerFingerprint: "provider-a")
        let providerBResults = await store.query(query, providerFingerprint: "provider-b")

        #expect(providerAResults.count == 1)
        #expect(providerAResults.first?.video.id == 1)
        #expect(providerBResults.count == 1)
        #expect(providerBResults.first?.video.id == 2)
    }

    @Test
    func scopeFilteringAndGenreFilters() async {
        let store = SearchIndexStore()
        await store.upsert(
            videos: [makeSnapshot(id: 10, name: "Space Patrol", contentType: "vod")],
            contentType: .vod,
            categoryID: "1",
            categoryName: "Sci-Fi",
            providerFingerprint: "provider"
        )
        await store.upsert(
            videos: [makeSnapshot(id: 20, name: "Royal House", contentType: "series")],
            contentType: .series,
            categoryID: "2",
            categoryName: "Drama",
            providerFingerprint: "provider"
        )

        let moviesOnly = await store.query(
            SearchQuery(text: "", scope: .movies, filters: .default, sort: .title),
            providerFingerprint: "provider"
        )
        #expect(moviesOnly.count == 1)
        #expect(moviesOnly.first?.video.id == 10)

        var dramaFilters = SearchFilters.default
        dramaFilters.genres = ["Drama"]
        let dramaResults = await store.query(
            SearchQuery(text: "", scope: .all, filters: dramaFilters, sort: .title),
            providerFingerprint: "provider"
        )
        #expect(dramaResults.count == 1)
        #expect(dramaResults.first?.video.id == 20)
    }

    @Test
    func progressTracksIndexedCategories() async {
        let store = SearchIndexStore()
        await store.upsert(
            videos: [makeSnapshot(id: 1, name: "One", contentType: "vod")],
            contentType: .vod,
            categoryID: "a",
            categoryName: "Action",
            providerFingerprint: "provider"
        )
        await store.upsert(
            videos: [makeSnapshot(id: 2, name: "Two", contentType: "vod")],
            contentType: .vod,
            categoryID: "b",
            categoryName: "Comedy",
            providerFingerprint: "provider"
        )

        let progress = await store.progress(scope: .movies, providerFingerprint: "provider", totalCategories: 3)
        #expect(progress.indexedCategories == 2)
        #expect(progress.totalCategories == 3)
        #expect(progress.scope == .movies)
    }

    @Test
    func queryPreservesPlaybackTypeAndStableIdentityAcrossMediaScopes() async {
        let store = SearchIndexStore()

        await store.upsert(
            videos: [makeSnapshot(id: 7, name: "Shared ID Movie", contentType: "movie")],
            contentType: .vod,
            categoryID: "movies",
            categoryName: "Action",
            providerFingerprint: "provider"
        )

        await store.upsert(
            videos: [makeSnapshot(id: 7, name: "Shared ID Series", contentType: "series")],
            contentType: .series,
            categoryID: "series",
            categoryName: "Drama",
            providerFingerprint: "provider"
        )

        let results = await store.query(
            SearchQuery(text: "shared", scope: .all, filters: .default, sort: .title),
            providerFingerprint: "provider"
        )

        #expect(results.count == 2)
        #expect(Set(results.map(\.id)).count == 2)

        let movie = results.first { $0.video.xtreamContentType == .vod }
        #expect(movie?.video.contentType == "movie")
    }

    @Test
    func categoryFilteringRespectsScopeAndSelectedCategory() async {
        let store = SearchIndexStore()

        await store.upsert(
            videos: [makeSnapshot(id: 1, name: "Action Movie", contentType: "vod")],
            contentType: .vod,
            categoryID: "action",
            categoryName: "Action",
            providerFingerprint: "provider"
        )
        await store.upsert(
            videos: [makeSnapshot(id: 2, name: "Comedy Movie", contentType: "vod")],
            contentType: .vod,
            categoryID: "comedy",
            categoryName: "Comedy",
            providerFingerprint: "provider"
        )
        await store.upsert(
            videos: [makeSnapshot(id: 3, name: "Action Series", contentType: "series")],
            contentType: .series,
            categoryID: "action",
            categoryName: "Action",
            providerFingerprint: "provider"
        )

        var filters = SearchFilters.default
        filters.categoryIDs = ["action"]

        let movieResults = await store.query(
            SearchQuery(text: "", scope: .movies, filters: filters, sort: .title),
            providerFingerprint: "provider"
        )
        #expect(movieResults.map(\.video.id) == [1])

        let seriesResults = await store.query(
            SearchQuery(text: "", scope: .series, filters: filters, sort: .title),
            providerFingerprint: "provider"
        )
        #expect(seriesResults.map(\.video.id) == [3])
    }

    @Test
    func categoryFilteringCombinesWithTextQuery() async {
        let store = SearchIndexStore()

        await store.upsert(
            videos: [
                makeSnapshot(id: 11, name: "Galaxy Patrol", contentType: "vod"),
                makeSnapshot(id: 12, name: "Galaxy Quest", contentType: "vod")
            ],
            contentType: .vod,
            categoryID: "scifi",
            categoryName: "Sci-Fi",
            providerFingerprint: "provider"
        )
        await store.upsert(
            videos: [makeSnapshot(id: 13, name: "Galaxy Patrol", contentType: "vod")],
            contentType: .vod,
            categoryID: "drama",
            categoryName: "Drama",
            providerFingerprint: "provider"
        )

        var filters = SearchFilters.default
        filters.categoryIDs = ["scifi"]

        let results = await store.query(
            SearchQuery(text: "patrol", scope: .movies, filters: filters, sort: .title),
            providerFingerprint: "provider"
        )

        #expect(results.map(\.video.id) == [11])
    }

    @Test
    func browseSortsOrderByTitleNewestAndRating() async {
        let store = SearchIndexStore()

        await store.upsert(
            videos: [
                makeSnapshot(id: 21, name: "Bravo", contentType: "vod", rating: 7.2, addedAtRaw: "2026-01-01"),
                makeSnapshot(id: 22, name: "Alpha", contentType: "vod", rating: 8.8, addedAtRaw: "2026-03-01"),
                makeSnapshot(id: 23, name: "Charlie", contentType: "vod", rating: 6.1, addedAtRaw: "2026-02-01")
            ],
            contentType: .vod,
            categoryID: "browse",
            categoryName: "Browse",
            providerFingerprint: "provider"
        )

        let titleResults = await store.query(
            SearchQuery(text: "", scope: .movies, filters: .default, sort: .title),
            providerFingerprint: "provider"
        )
        #expect(titleResults.map(\.video.id) == [22, 21, 23])

        let newestResults = await store.query(
            SearchQuery(text: "", scope: .movies, filters: .default, sort: .newest),
            providerFingerprint: "provider"
        )
        #expect(newestResults.map(\.video.id) == [22, 23, 21])

        let ratingResults = await store.query(
            SearchQuery(text: "", scope: .movies, filters: .default, sort: .rating),
            providerFingerprint: "provider"
        )
        #expect(ratingResults.map(\.video.id) == [22, 21, 23])
    }

    @Test
    func persistsProviderSnapshotsAcrossStoreInstances() async throws {
        let directoryURL = makeTemporaryDirectory()
        let providerFingerprint = "provider"

        let firstStore = SearchIndexStore(snapshotDirectoryURL: directoryURL)
        await firstStore.upsert(
            videos: [makeSnapshot(id: 31, name: "Persisted Movie", contentType: "vod")],
            contentType: .vod,
            categoryID: "persisted",
            categoryName: "Offline",
            providerFingerprint: providerFingerprint
        )

        let secondStore = SearchIndexStore(snapshotDirectoryURL: directoryURL)
        let results = await secondStore.query(
            SearchQuery(text: "persisted", scope: .movies, filters: .default, sort: .title),
            providerFingerprint: providerFingerprint
        )
        let progress = await secondStore.progress(
            scope: .movies,
            providerFingerprint: providerFingerprint,
            totalCategories: 1
        )

        #expect(results.map(\.video.id) == [31])
        #expect(progress.indexedCategories == 1)
    }

    @Test
    func corruptedSnapshotsAreDroppedDuringHydration() async throws {
        let directoryURL = makeTemporaryDirectory()
        let providerFingerprint = "provider"

        let store = SearchIndexStore(snapshotDirectoryURL: directoryURL)
        await store.upsert(
            videos: [makeSnapshot(id: 41, name: "Corrupt Me", contentType: "vod")],
            contentType: .vod,
            categoryID: "corrupt",
            categoryName: "Offline",
            providerFingerprint: providerFingerprint
        )

        let snapshotDirectory = directoryURL.appending(path: "SearchIndexSnapshots", directoryHint: .isDirectory)
        let snapshotFile = try #require(
            FileManager.default.contentsOfDirectory(at: snapshotDirectory, includingPropertiesForKeys: nil).first
        )
        try Data("not-json".utf8).write(to: snapshotFile, options: [.atomic])

        let reloadedStore = SearchIndexStore(snapshotDirectoryURL: directoryURL)
        let results = await reloadedStore.query(
            SearchQuery(text: "corrupt", scope: .movies, filters: .default, sort: .title),
            providerFingerprint: providerFingerprint
        )

        #expect(results.isEmpty)
        #expect(FileManager.default.fileExists(atPath: snapshotFile.path()) == false)
    }

    private func makeSnapshot(
        id: Int,
        name: String,
        contentType: String,
        rating: Double = 7.2,
        addedAtRaw: String = "2026-02-01"
    ) -> SearchVideoSnapshot {
        SearchVideoSnapshot(
            id: id,
            name: name,
            containerExtension: "mp4",
            contentType: contentType,
            coverImageURL: nil,
            rating: rating,
            addedAtRaw: addedAtRaw,
            language: "EN"
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
