import Foundation
import SQLiteData
import Testing

@testable import iptv

@Suite("Library filter engine", .serialized)
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

    @Test func titleQueriesUseSharedTrimCaseDiacriticAndWhitespaceNormalization() {
        let media = [
            makeMedia(id: 1, sourceID: 100, title: "Café   del\tMar"),
            makeMedia(id: 2, sourceID: 101, title: "Cafe Racer"),
            makeMedia(id: 3, sourceID: 102, title: "Del Mar Archive"),
        ]
        let state = LibraryFilterState()
        let normalizedReference = LibraryQueryNormalizer.normalized(" cafe del mar ")

        #expect(LibraryQueryNormalizer.normalized("CAFÉ\t\tDEL   MAR") == normalizedReference)

        for query in [" cafe del mar ", "CAFÉ DEL MAR", "cafe\u{301}    del\nmar"] {
            #expect(
                LibraryFilterEngine
                    .filteredMedia(media, categories: [], state: state, query: query)
                    .map(\.sourceID) == [100],
                "Query \(query) should match the same local title row after shared normalization."
            )
        }
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

    @MainActor
    @Test func prefixVisibilityPersistsInDatabasePerProvider() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let firstProviderID = try insertProvider(name: "First", database: database)
            let secondProviderID = try insertProvider(name: "Second", database: database)
            let suiteName = "prefix-db-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }

            CategoryPrefixVisibilityStore.setHiddenGroupKeys(["NL"], for: firstProviderID, database: database, defaults: defaults)
            CategoryPrefixVisibilityStore.setHiddenGroupKeys(["EN"], for: secondProviderID, database: database, defaults: defaults)

            #expect(CategoryPrefixVisibilityStore.hiddenGroupKeys(for: firstProviderID, database: database, defaults: defaults) == ["NL"])
            #expect(CategoryPrefixVisibilityStore.hiddenGroupKeys(for: secondProviderID, database: database, defaults: defaults) == ["EN"])
        }
    }

    @MainActor
    @Test func prefixVisibilityMigratesLegacyProviderDefaults() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Legacy", database: database)
            let suiteName = "prefix-legacy-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(["NL", "EN"], forKey: "library.categoryPrefixVisibility.provider.\(providerID).hiddenGroups")

            let hiddenGroups = CategoryPrefixVisibilityStore.hiddenGroupKeys(for: providerID, database: database, defaults: defaults)
            let databaseCount = try database.read {
                try CategoryPrefixVisibility.where { $0.providerID.eq(providerID) }.fetchCount($0)
            }

            #expect(hiddenGroups == ["EN", "NL"])
            #expect(databaseCount == 2)
            #expect(defaults.stringArray(forKey: "library.categoryPrefixVisibility.provider.\(providerID).hiddenGroups") == nil)
        }
    }

    @MainActor
    private func withTestDatabase<T>(_ operation: (any DatabaseWriter) throws -> T) throws -> T {
        let database = try appDatabase()
        return try operation(database)
    }

    private func resetDatabase(_ database: any DatabaseWriter) throws {
        try database.write { db in
            try CategoryPrefixVisibility.delete().execute(db)
            try Provider.delete().execute(db)
        }
    }

    @discardableResult
    private func insertProvider(name: String, database: any DatabaseWriter) throws -> Provider.ID {
        let endpoint = try #require(URL(string: "https://example.com"))
        var providerID: Provider.ID?

        try database.write { db in
            let provider = try Provider.insert {
                Provider.Draft(
                    id: nil,
                    kind: .xtream,
                    name: name,
                    username: "user",
                    password: "pass",
                    endpoint: endpoint,
                    isActive: false
                )
            }
            .returning(\.self)
            .fetchOne(db)!
            providerID = provider.id
        }

        return try #require(providerID)
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
