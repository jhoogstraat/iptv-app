import Foundation
import Testing

@testable import iptv

@Suite("Library filter engine")
struct LibraryFilterEngineTests {
    @Test func groupSelectionUsesORWithinGroupsAndANDAcrossOtherFilters() {
        let categories = [
            makeCategory(id: 1, title: "|EN| Action"),
            makeCategory(id: 2, title: "|NL| Drama"),
            makeCategory(id: 3, title: "Kids"),
        ]
        let media = [
            makeMedia(id: 1, sourceID: 100, title: "Alpha", categoryID: 1, rating: 8.4),
            makeMedia(id: 2, sourceID: 101, title: "Beta", categoryID: 2, rating: 8.1),
            makeMedia(id: 3, sourceID: 102, title: "Gamma", categoryID: 3, rating: 9.0),
            makeMedia(id: 4, sourceID: 103, title: "Delta", categoryID: 1, rating: 6.9),
        ]

        let groupOnly = LibraryFilterState(selectedGroupKeys: ["EN", "NL"])
        #expect(LibraryFilterEngine.filteredMedia(media, categories: categories, state: groupOnly).map(\.sourceID) == [100, 101, 103])

        let categoryAndRating = LibraryFilterState(
            selectedCategoryID: 1,
            selectedGroupKeys: ["EN", "NL"],
            minimumRating: 8.0
        )
        #expect(LibraryFilterEngine.filteredMedia(media, categories: categories, state: categoryAndRating).map(\.sourceID) == [100])
    }

    @Test func minimumRatingExcludesMissingRatings() {
        let categories = [makeCategory(id: 1, title: "|EN| Action")]
        let media = [
            makeMedia(id: 1, sourceID: 100, title: "Rated", categoryID: 1, rating: 8.0),
            makeMedia(id: 2, sourceID: 101, title: "Missing", categoryID: 1, rating: nil),
        ]
        let state = LibraryFilterState(minimumRating: 7.0)

        #expect(LibraryFilterEngine.filteredMedia(media, categories: categories, state: state).map(\.sourceID) == [100])
    }

    @Test func hiddenGroupsExcludeOtherwiseMatchingMedia() {
        let categories = [
            makeCategory(id: 1, title: "|EN| Action"),
            makeCategory(id: 2, title: "|NL| Drama"),
        ]
        let media = [
            makeMedia(id: 1, sourceID: 100, title: "Alpha", categoryID: 1, rating: 8.0),
            makeMedia(id: 2, sourceID: 101, title: "Beta", categoryID: 2, rating: 8.0),
        ]
        let state = LibraryFilterState(selectedGroupKeys: ["EN", "NL"], minimumRating: 7.0)

        #expect(
            LibraryFilterEngine
                .filteredMedia(media, categories: categories, state: state, hiddenGroupKeys: ["NL"])
                .map(\.sourceID) == [100]
        )
    }

    @Test func titleSortUsesSourceIDTieBreaker() {
        let media = [
            makeMedia(id: 1, sourceID: 200, title: "Same"),
            makeMedia(id: 2, sourceID: 100, title: "Same"),
            makeMedia(id: 3, sourceID: 300, title: "Alpha"),
        ]
        let state = LibraryFilterState(sort: .title)

        #expect(LibraryFilterEngine.filteredMedia(media, categories: [], state: state).map(\.sourceID) == [300, 100, 200])
    }

    @Test func newestSortFallsBackToTitleThenSourceID() {
        let newest = Date(timeIntervalSince1970: 200)
        let older = Date(timeIntervalSince1970: 100)
        let media = [
            makeMedia(id: 1, sourceID: 300, title: "Bravo", updatedAt: newest),
            makeMedia(id: 2, sourceID: 200, title: "Alpha", updatedAt: newest),
            makeMedia(id: 3, sourceID: 100, title: "Alpha", updatedAt: newest),
            makeMedia(id: 4, sourceID: 400, title: "Zulu", updatedAt: older),
        ]
        let state = LibraryFilterState(sort: .newest)

        #expect(LibraryFilterEngine.filteredMedia(media, categories: [], state: state).map(\.sourceID) == [100, 200, 300, 400])
    }

    @Test func ratingSortPlacesRatedItemsFirstAndUsesTitleTieBreaker() {
        let media = [
            makeMedia(id: 1, sourceID: 300, title: "Bravo", rating: 9.0),
            makeMedia(id: 2, sourceID: 200, title: "Alpha", rating: 9.0),
            makeMedia(id: 3, sourceID: 100, title: "Alpha", rating: 9.0),
            makeMedia(id: 4, sourceID: 400, title: "Unrated", rating: nil),
        ]
        let state = LibraryFilterState(sort: .rating)

        #expect(LibraryFilterEngine.filteredMedia(media, categories: [], state: state).map(\.sourceID) == [100, 200, 300, 400])
    }

    private func makeCategory(id: iptv.Category.ID, title: String) -> iptv.Category {
        iptv.Category(id: id, sourceID: "category-\(id)", type: .movie, title: title, updatedAt: nil)
    }

    private func makeMedia(
        id: iptv.Media.ID,
        sourceID: Int,
        title: String,
        categoryID: iptv.Category.ID? = nil,
        rating: Double? = nil,
        updatedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> iptv.Media {
        iptv.Media(
            id: id,
            sourceID: sourceID,
            type: .movie,
            title: title,
            categoryID: categoryID,
            tmdbID: nil,
            coverURL: nil,
            rating: rating,
            updatedAt: updatedAt
        )
    }
}
