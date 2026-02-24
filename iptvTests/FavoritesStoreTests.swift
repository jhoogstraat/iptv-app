//
//  FavoritesStoreTests.swift
//  iptvTests
//
//  Created by Codex on 24.02.26.
//

import Foundation
import Testing
@testable import iptv

struct FavoritesStoreTests {
    @Test
    func addAndRemoveFavorites() async {
        let fileURL = temporaryFileURL()
        let store = DiskFavoritesStore(fileURL: fileURL)
        let input = FavoriteInput(
            videoID: 42,
            contentType: XtreamContentType.vod.rawValue,
            title: "Demo",
            coverImageURL: nil,
            containerExtension: "mp4",
            rating: 8.0
        )

        await store.add(input: input, providerFingerprint: "provider-a")
        let afterAdd = await store.loadAll()
        #expect(afterAdd.count == 1)
        #expect(afterAdd.first?.videoID == 42)

        await store.remove(input: input, providerFingerprint: "provider-a")
        let afterRemove = await store.loadAll()
        #expect(afterRemove.isEmpty)
    }

    @Test
    func providerIsolation() async {
        let fileURL = temporaryFileURL()
        let store = DiskFavoritesStore(fileURL: fileURL)

        let first = FavoriteInput(
            videoID: 1,
            contentType: XtreamContentType.vod.rawValue,
            title: "One",
            coverImageURL: nil,
            containerExtension: "mp4",
            rating: nil
        )
        let second = FavoriteInput(
            videoID: 2,
            contentType: XtreamContentType.series.rawValue,
            title: "Two",
            coverImageURL: nil,
            containerExtension: "mp4",
            rating: nil
        )

        await store.add(input: first, providerFingerprint: "provider-a")
        await store.add(input: second, providerFingerprint: "provider-b")
        await store.clear(for: "provider-a")

        let records = await store.loadAll()
        #expect(records.count == 1)
        #expect(records.first?.providerFingerprint == "provider-b")
        #expect(records.first?.videoID == 2)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "favorites-tests-\(UUID().uuidString)", directoryHint: .notDirectory)
            .appendingPathExtension("json")
    }
}

