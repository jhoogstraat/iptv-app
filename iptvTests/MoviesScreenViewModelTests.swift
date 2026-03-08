//
//  MoviesScreenViewModelTests.swift
//  iptvTests
//
//  Created by Codex on 08.03.26.
//

import Foundation
import Testing
@testable import iptv

@MainActor
struct MoviesScreenViewModelTests {
    @Test
    func loadFetchesCategoriesThenAutoSelectsFirstCategory() async {
        let action = Category(id: "1", name: "Action")
        let drama = Category(id: "2", name: "Drama")
        let catalog = MoviesBrowsingCatalogSpy()
        catalog.categoriesByType[.vod] = [action, drama]
        catalog.cachedVideosByKey["vod:1"] = [makeVideo(id: 10, name: "Alpha")]

        let viewModel = MoviesScreenViewModel(contentType: .vod, catalog: catalog)
        await viewModel.load(force: true)

        #expect(catalog.recordedEvents == [
            .getCategories(.vod, true),
            .getStreams(.vod, "1", true)
        ])
        #expect(viewModel.selectedCategoryID == "1")
        #expect(viewModel.browseResults.map(\.id) == [10])
    }

    @Test
    func selectingNewCategoryLoadsOnlyThatCategoryOnce() async {
        let action = Category(id: "1", name: "Action")
        let drama = Category(id: "2", name: "Drama")
        let catalog = MoviesBrowsingCatalogSpy()
        catalog.categoriesByType[.vod] = [action, drama]
        catalog.cachedVideosByKey["vod:1"] = [makeVideo(id: 10, name: "Alpha")]
        catalog.fetchedVideosByKey["vod:2"] = [makeVideo(id: 20, name: "Beta")]

        let viewModel = MoviesScreenViewModel(contentType: .vod, catalog: catalog)
        await viewModel.load(force: false)
        catalog.recordedEvents.removeAll()

        await viewModel.selectCategory(id: "2")

        #expect(catalog.recordedEvents == [
            .getStreams(.vod, "2", false)
        ])
        #expect(viewModel.selectedCategoryID == "2")
        #expect(viewModel.browseResults.map(\.id) == [20])
    }

    @Test
    func reselectingLoadedCategoryUsesCachedVideosWithoutFetchingAgain() async {
        let action = Category(id: "1", name: "Action")
        let drama = Category(id: "2", name: "Drama")
        let catalog = MoviesBrowsingCatalogSpy()
        catalog.categoriesByType[.vod] = [action, drama]
        catalog.cachedVideosByKey["vod:1"] = [makeVideo(id: 10, name: "Alpha")]
        catalog.cachedVideosByKey["vod:2"] = [makeVideo(id: 20, name: "Beta")]

        let viewModel = MoviesScreenViewModel(contentType: .vod, catalog: catalog)
        await viewModel.load(force: false)
        await viewModel.selectCategory(id: "2")
        catalog.recordedEvents.removeAll()

        await viewModel.selectCategory(id: "1")

        #expect(catalog.recordedEvents.isEmpty)
        #expect(viewModel.selectedCategoryID == "1")
        #expect(viewModel.browseResults.map(\.id) == [10])
    }

    @Test
    func providerRevisionStyleReloadReselectsFirstValidCategory() async {
        let oldCategory = Category(id: "old", name: "Old")
        let newCategory = Category(id: "new", name: "New")
        let catalog = MoviesBrowsingCatalogSpy()
        catalog.categoriesByType[.vod] = [oldCategory]
        catalog.cachedVideosByKey["vod:old"] = [makeVideo(id: 10, name: "Legacy")]

        let viewModel = MoviesScreenViewModel(contentType: .vod, catalog: catalog)
        await viewModel.load(force: false)

        catalog.categoriesByType[.vod] = [newCategory]
        catalog.cachedVideosByKey["vod:new"] = [makeVideo(id: 20, name: "Fresh")]
        catalog.recordedEvents.removeAll()

        await viewModel.load(force: true)

        #expect(viewModel.selectedCategoryID == "new")
        #expect(viewModel.browseResults.map(\.id) == [20])
        #expect(catalog.recordedEvents == [
            .getCategories(.vod, true),
            .getStreams(.vod, "new", true)
        ])
    }

    @Test
    func queryAndSortApplyWithinSelectedCategoryOnly() async {
        let category = Category(id: "1", name: "Action")
        let catalog = MoviesBrowsingCatalogSpy()
        catalog.categoriesByType[.vod] = [category]
        catalog.cachedVideosByKey["vod:1"] = [
            makeVideo(id: 1, name: "Zulu", rating: 6.0, addedAtRaw: "2026-01-01"),
            makeVideo(id: 2, name: "Alpha Patrol", rating: 8.0, addedAtRaw: "2026-03-01"),
            makeVideo(id: 3, name: "Bravo Patrol", rating: 7.0, addedAtRaw: "2026-02-01")
        ]

        let viewModel = MoviesScreenViewModel(contentType: .vod, catalog: catalog)
        await viewModel.load(force: false)
        viewModel.queryText = "patrol"
        viewModel.browseSort = .rating

        #expect(viewModel.browseResults.map(\.id) == [2, 3])
    }

    private func makeVideo(
        id: Int,
        name: String,
        rating: Double? = 7.0,
        addedAtRaw: String? = nil
    ) -> Video {
        Video(
            id: id,
            name: name,
            containerExtension: "mp4",
            contentType: XtreamContentType.vod.rawValue,
            coverImageURL: nil,
            tmdbId: nil,
            rating: rating,
            addedAtRaw: addedAtRaw
        )
    }
}

@MainActor
private final class MoviesBrowsingCatalogSpy: MoviesBrowsingCatalog {
    enum Event: Equatable {
        case getCategories(XtreamContentType, Bool)
        case getStreams(XtreamContentType, String, Bool)
    }

    var categoriesByType: [XtreamContentType: [iptv.Category]] = [:]
    var cachedVideosByKey: [String: [Video]] = [:]
    var fetchedVideosByKey: [String: [Video]] = [:]
    var recordedEvents: [Event] = []

    func getCategories(for contentType: XtreamContentType, force: Bool) async throws {
        recordedEvents.append(.getCategories(contentType, force))
    }

    func categories(for contentType: XtreamContentType) -> [iptv.Category] {
        categoriesByType[contentType] ?? []
    }

    func getStreams(in category: iptv.Category, contentType: XtreamContentType, force: Bool) async throws {
        recordedEvents.append(.getStreams(contentType, category.id, force))
        let key = "\(contentType.rawValue):\(category.id)"
        if let fetchedVideos = fetchedVideosByKey[key] {
            cachedVideosByKey[key] = fetchedVideos
        }
    }

    func cachedVideos(in category: iptv.Category, contentType: XtreamContentType) -> [Video]? {
        cachedVideosByKey["\(contentType.rawValue):\(category.id)"]
    }
}
