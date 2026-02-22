//
//  WatchActivityStoreTests.swift
//  iptvTests
//
//  Created by Codex on 22.02.26.
//

import Foundation
import Testing
@testable import iptv

struct WatchActivityStoreTests {
    @Test
    func persistsAndLoadsProgress() async throws {
        let fileURL = temporaryFileURL()
        let store = DiskWatchActivityStore(fileURL: fileURL)

        let input = WatchActivityInput(
            videoID: 101,
            contentType: "movie",
            title: "Demo Movie",
            coverImageURL: "https://example.com/cover.jpg",
            containerExtension: "mp4",
            rating: 8.1
        )

        await store.recordProgress(input: input, providerFingerprint: "provider-a", currentTime: 120, duration: 600)

        let records = await store.loadAll()
        #expect(records.count == 1)

        let record = try #require(records.first)
        #expect(record.providerFingerprint == "provider-a")
        #expect(record.videoID == 101)
        #expect(record.progressFraction > 0.19)
        #expect(record.progressFraction < 0.21)
    }

    @Test
    func marksCompletedAndFiltersByProvider() async throws {
        let fileURL = temporaryFileURL()
        let store = DiskWatchActivityStore(fileURL: fileURL)

        let input = WatchActivityInput(
            videoID: 55,
            contentType: "series",
            title: "Demo Series",
            coverImageURL: nil,
            containerExtension: "mp4",
            rating: 7.4
        )

        await store.recordProgress(input: input, providerFingerprint: "provider-a", currentTime: 50, duration: 100)
        await store.markCompleted(input: input, providerFingerprint: "provider-a")
        await store.recordProgress(input: input, providerFingerprint: "provider-b", currentTime: 30, duration: 100)

        var records = await store.loadAll()
        #expect(records.count == 2)
        #expect(records.contains { $0.providerFingerprint == "provider-a" && $0.isCompleted })

        await store.clear(for: "provider-a")
        records = await store.loadAll()
        #expect(records.count == 1)
        #expect(records.first?.providerFingerprint == "provider-b")
    }

    @Test
    func recoversFromCorruptFile() async throws {
        let fileURL = temporaryFileURL()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL, options: [.atomic])

        let store = DiskWatchActivityStore(fileURL: fileURL)
        let records = await store.loadAll()
        #expect(records.isEmpty)

        let input = WatchActivityInput(
            videoID: 9,
            contentType: "movie",
            title: "Recovery Movie",
            coverImageURL: nil,
            containerExtension: "mkv",
            rating: nil
        )

        await store.recordProgress(input: input, providerFingerprint: "provider-a", currentTime: 10, duration: 100)
        let updated = await store.loadAll()
        #expect(updated.count == 1)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "watch-activity-tests")
            .appending(path: "\(UUID().uuidString).json")
    }
}
