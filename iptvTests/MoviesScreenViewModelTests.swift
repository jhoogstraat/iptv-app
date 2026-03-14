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
        await viewModel.load(policy: .refreshNow)

        #expect(catalog.recordedEvents == [
            .getCategories(.vod, .refreshNow),
            .getStreams(.vod, "1", .refreshNow)
        ])
        #expect(viewModel.selectedCategoryID == "1")
        #expect(viewModel.browseResults.map(\.id) == [10])
        if case .done = viewModel.phase {
            #expect(true)
        } else {
            Issue.record("Expected view model to finish loading")
        }
        #expect(viewModel.isSelectedCategoryLoading == false)
        #expect(viewModel.selectedCategoryError == nil)
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
        await viewModel.load(policy: .cachedThenRefresh)
        catalog.recordedEvents.removeAll()

        await viewModel.selectCategory(id: "2")

        #expect(catalog.recordedEvents == [
            .getStreams(.vod, "2", .cachedThenRefresh)
        ])
        #expect(viewModel.selectedCategoryID == "2")
        #expect(viewModel.browseResults.map(\.id) == [20])
        #expect(viewModel.isSelectedCategoryLoading == false)
    }

    @Test
    func reselectingLoadedCategoryShowsCachedVideosAndRefreshesInBackground() async {
        let action = Category(id: "1", name: "Action")
        let drama = Category(id: "2", name: "Drama")
        let catalog = MoviesBrowsingCatalogSpy()
        catalog.categoriesByType[.vod] = [action, drama]
        catalog.cachedVideosByKey["vod:1"] = [makeVideo(id: 10, name: "Alpha")]
        catalog.cachedVideosByKey["vod:2"] = [makeVideo(id: 20, name: "Beta")]

        let viewModel = MoviesScreenViewModel(contentType: .vod, catalog: catalog)
        await viewModel.load(policy: .cachedThenRefresh)
        await viewModel.selectCategory(id: "2")
        catalog.recordedEvents.removeAll()

        await viewModel.selectCategory(id: "1")

        #expect(catalog.recordedEvents == [
            .getStreams(.vod, "1", .refreshNow)
        ])
        #expect(viewModel.selectedCategoryID == "1")
        #expect(viewModel.browseResults.map(\.id) == [10])
        #expect(viewModel.selectedCategoryError == nil)
    }

    @Test
    func cachedLoadKeepsBrowseShellVisibleWhileRefreshRuns() async {
        let action = Category(id: "1", name: "Action")
        let catalog = MoviesBrowsingCatalogSpy()
        catalog.categoriesByType[.vod] = [action]
        catalog.cachedVideosByKey["vod:1"] = [makeVideo(id: 10, name: "Alpha")]
        catalog.streamDelay = .milliseconds(200)

        let viewModel = MoviesScreenViewModel(contentType: .vod, catalog: catalog)
        let loadTask = Task { await viewModel.load(policy: .cachedThenRefresh) }

        try? await Task.sleep(for: .milliseconds(40))

        if case .done = viewModel.phase {
            #expect(true)
        } else {
            Issue.record("Expected cached load to keep the browse shell visible")
        }
        #expect(viewModel.categories.map(\.id) == ["1"])
        #expect(viewModel.browseResults.map(\.id) == [10])
        #expect(viewModel.isSelectedCategoryLoading == false)
        #expect(viewModel.selectedCategoryError == nil)

        await loadTask.value
    }

    @Test
    func uncachedSelectedCategoryShowsSkeletonStateUntilFetchCompletes() async {
        let action = Category(id: "1", name: "Action")
        let catalog = MoviesBrowsingCatalogSpy()
        catalog.categoriesByType[.vod] = [action]
        catalog.fetchedVideosByKey["vod:1"] = [makeVideo(id: 10, name: "Alpha")]
        catalog.streamDelay = .milliseconds(200)

        let viewModel = MoviesScreenViewModel(contentType: .vod, catalog: catalog)
        let loadTask = Task { await viewModel.load(policy: .cachedThenRefresh) }

        try? await Task.sleep(for: .milliseconds(40))

        if case .done = viewModel.phase {
            #expect(true)
        } else {
            Issue.record("Expected uncached category load to stay in shell mode")
        }
        #expect(viewModel.categories.map(\.id) == ["1"])
        #expect(viewModel.browseResults.isEmpty)
        #expect(viewModel.isSelectedCategoryLoading)
        #expect(viewModel.selectedCategoryError == nil)

        await loadTask.value

        #expect(viewModel.browseResults.map(\.id) == [10])
        #expect(viewModel.isSelectedCategoryLoading == false)
    }

    @Test
    func providerRevisionStyleReloadReselectsFirstValidCategory() async {
        let oldCategory = Category(id: "old", name: "Old")
        let newCategory = Category(id: "new", name: "New")
        let catalog = MoviesBrowsingCatalogSpy()
        catalog.categoriesByType[.vod] = [oldCategory]
        catalog.cachedVideosByKey["vod:old"] = [makeVideo(id: 10, name: "Legacy")]

        let viewModel = MoviesScreenViewModel(contentType: .vod, catalog: catalog)
        await viewModel.load(policy: .cachedThenRefresh)

        catalog.categoriesByType[.vod] = [newCategory]
        catalog.cachedVideosByKey["vod:new"] = [makeVideo(id: 20, name: "Fresh")]
        catalog.recordedEvents.removeAll()

        await viewModel.load(policy: .refreshNow)

        #expect(viewModel.selectedCategoryID == "new")
        #expect(viewModel.browseResults.map(\.id) == [20])
        #expect(catalog.recordedEvents == [
            .getCategories(.vod, .refreshNow),
            .getStreams(.vod, "new", .refreshNow)
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
        await viewModel.load(policy: .cachedThenRefresh)
        viewModel.queryText = "patrol"
        viewModel.browseSort = .rating

        #expect(viewModel.browseResults.map(\.id) == [2, 3])
    }

    @Test
    func categoryMenuSectionsGroupPrefixedCategoriesByLanguageAndStripPrefixes() {
        let catalog = MoviesBrowsingCatalogSpy()
        catalog.categoriesByType[.vod] = [
            Category(id: "1", name: "Action"),
            Category(id: "2", name: "|NL| Drama"),
            Category(id: "3", name: "|NL| Comedy"),
            Category(id: "4", name: "|MULTI| Thriller")
        ]

        let viewModel = MoviesScreenViewModel(contentType: .vod, catalog: catalog)

        #expect(viewModel.categoryMenuSections.count == 3)
        #expect(viewModel.categoryMenuSections[0].title == nil)
        #expect(viewModel.categoryMenuSections[0].items.map(\.title) == ["Action"])
        #expect(viewModel.categoryMenuSections[1].title == "NL")
        #expect(viewModel.categoryMenuSections[1].items.map(\.title) == ["Drama", "Comedy"])
        #expect(viewModel.categoryMenuSections[2].title == "MULTI")
        #expect(viewModel.categoryMenuSections[2].items.map(\.title) == ["Thriller"])
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
        case getCategories(XtreamContentType, CatalogLoadPolicy)
        case getStreams(XtreamContentType, String, CatalogLoadPolicy)
    }

    var categoriesByType: [XtreamContentType: [iptv.Category]] = [:]
    var cachedVideosByKey: [String: [Video]] = [:]
    var fetchedVideosByKey: [String: [Video]] = [:]
    var recordedEvents: [Event] = []
    var streamDelay: Duration?

    func getCategories(for contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws {
        recordedEvents.append(.getCategories(contentType, policy))
    }

    func categories(for contentType: XtreamContentType) -> [iptv.Category] {
        categoriesByType[contentType] ?? []
    }

    func getStreams(in category: iptv.Category, contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws {
        recordedEvents.append(.getStreams(contentType, category.id, policy))
        if let streamDelay {
            try await Task.sleep(for: streamDelay)
        }
        let key = "\(contentType.rawValue):\(category.id)"
        if let fetchedVideos = fetchedVideosByKey[key] {
            cachedVideosByKey[key] = fetchedVideos
        }
    }

    func cachedVideos(in category: iptv.Category, contentType: XtreamContentType) -> [Video]? {
        cachedVideosByKey["\(contentType.rawValue):\(category.id)"]
    }
}
