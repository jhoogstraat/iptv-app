//
//  LocalRecommendationProviderTests.swift
//  iptvTests
//
//  Created by Codex on 22.02.26.
//

import Foundation
import Testing
@testable import iptv

@MainActor
struct LocalRecommendationProviderTests {
    @Test
    func buildsExpectedSectionOrderAndHero() async throws {
        let provider = LocalRecommendationProvider(ranker: LocalRecommendationRanker(now: Date(timeIntervalSince1970: 1_700_000_000)))
        let context = makeContext(includeWatchHistory: true, includeLargeCatalog: true)

        let output = try await provider.build(context: context)

        #expect(output.hero != nil)
        #expect(output.sections.first?.id == "continue-watching")

        let ids = output.sections.map(\.id)
        #expect(ids.contains("because-you-watched"))
        #expect(ids.contains("trending"))
        #expect(ids.contains("critically-acclaimed"))
        #expect(ids.contains("new-additions"))
        #expect(ids.contains("binge-worthy-series"))

        #expect(!ids.contains("live"))
        #expect(!ids.contains("downloads"))
        #expect(!ids.contains("favorites"))
        #expect(!ids.contains("search"))
    }

    @Test
    func fallsBackHeroWithoutWatchHistory() async throws {
        let provider = LocalRecommendationProvider(ranker: LocalRecommendationRanker(now: Date(timeIntervalSince1970: 1_700_000_000)))
        let context = makeContext(includeWatchHistory: false, includeLargeCatalog: true)

        let output = try await provider.build(context: context)

        #expect(output.hero != nil)
        #expect(output.sections.contains { $0.id == "trending" || $0.id == "critically-acclaimed" })
    }

    @Test
    func suppressesSmallRailsButKeepsContinueWatching() async throws {
        let provider = LocalRecommendationProvider(ranker: LocalRecommendationRanker(now: Date(timeIntervalSince1970: 1_700_000_000)))
        let context = makeContext(includeWatchHistory: true, includeLargeCatalog: false)

        let output = try await provider.build(context: context)

        #expect(output.sections.count == 1)
        #expect(output.sections.first?.id == "continue-watching")
    }

    private func makeContext(includeWatchHistory: Bool, includeLargeCatalog: Bool) -> RecommendationContext {
        let vodA = Category(id: "vod-a", name: "Action")
        let vodB = Category(id: "vod-b", name: "Thriller")
        let seriesA = Category(id: "series-a", name: "Drama")

        let count = includeLargeCatalog ? 14 : 4
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        var vodVideos: [Video] = []
        var thrillerVideos: [Video] = []
        var seriesVideos: [Video] = []

        for index in 1...count {
            vodVideos.append(
                Video(
                    id: index,
                    name: "EN Action \(index)",
                    containerExtension: "mp4",
                    contentType: "movie",
                    coverImageURL: nil,
                    tmdbId: nil,
                    rating: 7.5 + Double(index % 3),
                    addedAtRaw: String(Int(now.timeIntervalSince1970) - (index * 86_400))
                )
            )

            thrillerVideos.append(
                Video(
                    id: 100 + index,
                    name: "EN Thriller \(index)",
                    containerExtension: "mp4",
                    contentType: "movie",
                    coverImageURL: nil,
                    tmdbId: nil,
                    rating: 6.8 + Double(index % 4),
                    addedAtRaw: String(Int(now.timeIntervalSince1970) - (index * 43_200))
                )
            )

            seriesVideos.append(
                Video(
                    id: 200 + index,
                    name: "EN Series \(index)",
                    containerExtension: "mp4",
                    contentType: XtreamContentType.series.rawValue,
                    coverImageURL: nil,
                    tmdbId: nil,
                    rating: 7.2 + Double(index % 3),
                    addedAtRaw: String(Int(now.timeIntervalSince1970) - (index * 50_000))
                )
            )
        }

        let watchRecords: [WatchActivityRecord]
        if includeWatchHistory {
            watchRecords = [
                WatchActivityRecord(
                    providerFingerprint: "provider-a",
                    videoID: 1,
                    contentType: "movie",
                    title: "EN Action 1",
                    coverImageURL: nil,
                    containerExtension: "mp4",
                    rating: 8.0,
                    lastPositionSeconds: 180,
                    durationSeconds: 1_200,
                    progressFraction: 0.15,
                    lastPlayedAt: now,
                    isCompleted: false
                ),
                WatchActivityRecord(
                    providerFingerprint: "provider-a",
                    videoID: 2,
                    contentType: "movie",
                    title: "EN Action 2",
                    coverImageURL: nil,
                    containerExtension: "mp4",
                    rating: 7.9,
                    lastPositionSeconds: 420,
                    durationSeconds: 1_300,
                    progressFraction: 0.32,
                    lastPlayedAt: now.addingTimeInterval(-3_600),
                    isCompleted: false
                )
            ]
        } else {
            watchRecords = []
        }

        return RecommendationContext(
            providerFingerprint: "provider-a",
            watchRecords: watchRecords,
            vodCategories: [vodA, vodB],
            seriesCategories: [seriesA],
            vodCatalog: [
                vodA: vodVideos,
                vodB: thrillerVideos
            ],
            seriesCatalog: [
                seriesA: seriesVideos
            ]
        )
    }
}
