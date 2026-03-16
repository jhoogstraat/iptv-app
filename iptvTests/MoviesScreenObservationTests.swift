//
//  MoviesScreenObservationTests.swift
//  iptvTests
//
//  Created by Codex on 16.03.26.
//

import Foundation
import Testing
@testable import iptv

struct MoviesScreenObservationTests {
    @Test
    func categoryMenuSectionsGroupPrefixedCategoriesByLanguage() {
        let categories = [
            ObservedCategoryRow(id: "1", name: "Action", groupedDisplayName: "Action", languageGroupCode: nil),
            ObservedCategoryRow(id: "2", name: "|NL| Drama", groupedDisplayName: "Drama", languageGroupCode: "NL"),
            ObservedCategoryRow(id: "3", name: "|NL| Comedy", groupedDisplayName: "Comedy", languageGroupCode: "NL"),
            ObservedCategoryRow(id: "4", name: "|MULTI| Thriller", groupedDisplayName: "Thriller", languageGroupCode: "MULTI")
        ]

        let sections = buildMoviesCategoryMenuSections(from: categories)

        #expect(sections.count == 3)
        #expect(sections[0].title == nil)
        #expect(sections[0].items.map(\.title) == ["Action"])
        #expect(sections[1].title == "NL")
        #expect(sections[1].items.map(\.title) == ["Drama", "Comedy"])
        #expect(sections[2].title == "MULTI")
        #expect(sections[2].items.map(\.title) == ["Thriller"])
    }

    @Test
    func browseFilteringIsCaseAndDiacriticInsensitive() {
        let rows = [
            ObservedStreamRow(
                id: 1,
                title: "Amelie",
                normalizedTitle: "amelie",
                artworkURL: nil,
                ratingText: nil,
                languageText: nil,
                containerExtension: "mp4",
                contentType: XtreamContentType.vod.rawValue,
                coverImageURL: nil,
                tmdbId: nil,
                rating: nil,
                addedAtRaw: nil
            ),
            ObservedStreamRow(
                id: 2,
                title: "Zulu Patrol",
                normalizedTitle: "zulu patrol",
                artworkURL: nil,
                ratingText: nil,
                languageText: nil,
                containerExtension: "mp4",
                contentType: XtreamContentType.vod.rawValue,
                coverImageURL: nil,
                tmdbId: nil,
                rating: nil,
                addedAtRaw: nil
            )
        ]

        let results = filterMoviesBrowseRows(rows, queryText: "amél")

        #expect(results.map(\.id) == [1])
    }

    @Test
    func observedStreamRowMapsBackToVideo() {
        let row = ObservedStreamRow(
            id: 42,
            title: "Example",
            normalizedTitle: "example",
            artworkURL: URL(string: "https://example.com/cover.jpg"),
            ratingText: "8.5",
            languageText: "EN",
            containerExtension: "mkv",
            contentType: XtreamContentType.series.rawValue,
            coverImageURL: "https://example.com/cover.jpg",
            tmdbId: "123",
            rating: 8.5,
            addedAtRaw: "2026-03-15"
        )

        let video = row.asVideo()

        #expect(video.id == 42)
        #expect(video.name == "Example")
        #expect(video.containerExtension == "mkv")
        #expect(video.contentType == XtreamContentType.series.rawValue)
        #expect(video.coverImageURL == "https://example.com/cover.jpg")
        #expect(video.tmdbId == "123")
        #expect(video.rating == 8.5)
        #expect(video.addedAtRaw == "2026-03-15")
    }
}
