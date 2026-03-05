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

    private func makeSnapshot(id: Int, name: String, contentType: String) -> SearchVideoSnapshot {
        SearchVideoSnapshot(
            id: id,
            name: name,
            containerExtension: "mp4",
            contentType: contentType,
            coverImageURL: nil,
            rating: 7.2,
            addedAtRaw: "2026-02-01",
            language: "EN"
        )
    }
}
