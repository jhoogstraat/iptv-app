import Foundation
import SQLiteData
import Testing

@testable import iptv

@Suite("Library filter engine", .serialized)
struct LibraryFilterEngineTests {
    @Test func categoryContextRejectsRowsFromAnUnscopedInitialSnapshot() {
        let selectedCategory = makeCategory(id: 1, title: "Action")
        let media = [
            makeMedia(id: 1, sourceID: 100, title: "Selected", categoryID: selectedCategory.id),
            makeMedia(id: 2, sourceID: 101, title: "Previously Loaded", categoryID: 2),
        ]

        let result = LibraryFilterEngine.filteredMedia(
            media,
            categories: [selectedCategory],
            state: LibraryFilterState(selectedCategoryID: selectedCategory.id)
        )

        #expect(result.map(\.sourceID) == [100])
    }

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

    @Test func backgroundFilteringPreservesSynchronousSemanticsAndOrder() async {
        let categories = [
            makeCategory(id: 1, title: "|EN| Action"),
            makeCategory(id: 2, title: "|NL| Drama"),
        ]
        let media = [
            makeMedia(id: 1, sourceID: 100, title: "Alpha", categoryID: 1, rating: 8.4),
            makeMedia(id: 2, sourceID: 101, title: "Beta", categoryID: 2, rating: 9.5),
            makeMedia(id: 3, sourceID: 102, title: "Bravo", categoryID: 1, rating: 9.0),
            makeMedia(id: 4, sourceID: 103, title: "Charlie", categoryID: 1, rating: 7.9),
        ]
        let request = LibraryFilterRequest(
            media: media,
            categories: categories,
            state: LibraryFilterState(
                selectedCategoryID: 1,
                selectedGroupKeys: ["EN"],
                minimumRating: 8,
                sort: .rating
            ),
            hiddenGroupKeys: ["NL"],
            query: "a"
        )

        let backgroundResult = await LibraryFilterEngine.filteredMedia(inBackground: request)
        let synchronousResult = LibraryFilterEngine.filteredMedia(
            request.media,
            categories: request.categories,
            state: request.state,
            hiddenGroupKeys: request.hiddenGroupKeys,
            query: request.query
        )

        #expect(backgroundResult.map(\.id) == synchronousResult.map(\.id))
        #expect(backgroundResult.map(\.sourceID) == [102, 100])
    }

    @Test func backgroundFilteringRestrictsResultsToRequestedMediaTypes() async {
        let media = [
            makeMedia(id: 1, sourceID: 100, type: .movie, title: "Shared Title"),
            makeMedia(id: 2, sourceID: 101, type: .series, title: "Shared Title"),
            makeMedia(id: 3, sourceID: 102, type: .live, title: "Shared Title"),
        ]
        let request = LibraryFilterRequest(
            media: media,
            categories: [],
            state: LibraryFilterState(),
            hiddenGroupKeys: [],
            query: "shared",
            includedTypes: [.movie, .series]
        )

        let result = await LibraryFilterEngine.filteredMedia(inBackground: request)

        #expect(result.map(\.type) == [.movie, .series])
    }

    @Test func cancellingBackgroundFilteringCancelsItsDetachedWorker() async {
        let media = (0..<50_000).map { index in
            makeMedia(
                id: index + 1,
                sourceID: index + 1,
                title: "Large Catalog Entry \(index)"
            )
        }
        let request = LibraryFilterRequest(
            media: media,
            categories: [],
            state: LibraryFilterState(),
            hiddenGroupKeys: [],
            query: "catalog"
        )
        let task = Task {
            await LibraryFilterEngine.filteredMedia(inBackground: request)
        }

        task.cancel()
        let result = await task.value

        #expect(result.isEmpty)
    }

    @Test func compactTaskIdentityNormalizesQueriesAndTracksCatalogRevision() {
        let state = LibraryFilterState(selectedGroupKeys: ["EN"], sort: .rating)
        let first = LibraryFilterTaskID(
            state: state,
            hiddenGroupKeys: ["NL"],
            query: " Café  News ",
            includedTypes: [.movie],
            catalogRevision: 4
        )
        let equivalent = LibraryFilterTaskID(
            state: state,
            hiddenGroupKeys: ["NL"],
            query: "cafe news",
            includedTypes: [.movie],
            catalogRevision: 4
        )
        let refreshedCatalog = LibraryFilterTaskID(
            state: state,
            hiddenGroupKeys: ["NL"],
            query: "cafe news",
            includedTypes: [.movie],
            catalogRevision: 5
        )

        #expect(first == equivalent)
        #expect(first != refreshedCatalog)
    }

    @Test func hiddenCategoryRelationshipsRemainAvailableAcrossLibraryProjections() {
        for (offset, type) in [MediaType.movie, .series, .live].enumerated() {
            let base = offset * 10
            let categories = [
                makeCategory(id: base + 1, type: type, title: "|EN| Visible"),
                makeCategory(id: base + 2, type: type, title: "|NL| Hidden"),
                makeCategory(id: base + 3, type: type, title: "Actually Ungrouped"),
            ]
            let media = [
                makeMedia(id: base + 1, sourceID: base + 100, type: type, title: "Alpha", categoryID: base + 1),
                makeMedia(id: base + 2, sourceID: base + 101, type: type, title: "Beta", categoryID: base + 2),
                makeMedia(id: base + 3, sourceID: base + 102, type: type, title: "Gamma", categoryID: base + 3),
            ]
            let projection = LibraryCategoryProjection(
                categories: categories,
                hiddenGroupKeys: ["NL"],
                includedTypes: [type]
            )

            #expect(Set(projection.selectableCategories.map(\.id)) == [base + 1, base + 3])
            #expect(projection.categoryByID[base + 2]?.title == "|NL| Hidden")
            #expect(
                LibraryFilterEngine.filteredMedia(
                    media,
                    categories: categories,
                    state: LibraryFilterState(),
                    hiddenGroupKeys: ["NL"]
                ).map(\.sourceID) == [base + 100, base + 102]
            )
        }
    }

    @Test func categoryPrefixMustStartAtBeginningOfTitle() {
        #expect(CategoryGrouping.key(for: "|NL| Movies") == "NL")
        #expect(CategoryGrouping.key(for: "Movies |NL| Archive") == CategoryGrouping.ungroupedKey)
        #expect(CategoryGrouping.key(for: "  |NL| Movies") == CategoryGrouping.ungroupedKey)
    }

    @Test func categoryDisplayTitleUsesPersistedGroupKeyWithoutDestroyingRawTitle() {
        #expect(CategoryGrouping.categoryTitle(for: "|NL| Movies", groupKey: "NL") == "Movies")
        #expect(CategoryGrouping.categoryTitle(for: "|NL|", groupKey: "NL") == "|NL|")
        #expect(
            CategoryGrouping.categoryTitle(
                for: "Movies |NL| Archive",
                groupKey: CategoryGrouping.ungroupedKey
            ) == "Movies |NL| Archive"
        )
        #expect(CategoryGrouping.categoryTitle(for: "|NL| Movies", groupKey: "EN") == "|NL| Movies")
    }

    @Test func clearFiltersAlsoRestoresDefaultSort() {
        var state = LibraryFilterState(
            selectedCategoryID: 9,
            selectedGroupKeys: ["NL"],
            minimumRating: 8,
            sort: .rating
        )

        state.clearFilters()

        #expect(state == LibraryFilterState())
    }

    @Test func scopeChangeInvalidatesIncompatibleCategoryAndGroups() {
        let categories = [
            makeCategory(id: 1, type: .movie, title: "|MOV| Movies"),
            makeCategory(id: 2, type: .series, title: "|SER| Series"),
        ]
        let seriesProjection = LibraryCategoryProjection(
            categories: categories,
            hiddenGroupKeys: [],
            includedTypes: LibrarySearchScope.series.includedTypes
        )
        var state = LibraryFilterState(
            selectedCategoryID: 1,
            selectedGroupKeys: ["MOV"],
            sort: .newest
        )

        state.retainSelections(availableIn: seriesProjection.selectableCategories)

        #expect(state.selectedCategoryID == nil)
        #expect(state.selectedGroupKeys.isEmpty)
        #expect(state.sort == .newest)
    }

    @Test func categorySelectionClearsWhenSelectedGroupsExcludeItsGroup() {
        let categories = [
            makeCategory(id: 1, title: "|EN| Action"),
            makeCategory(id: 2, title: "|NL| Drama"),
        ]
        var state = LibraryFilterState(
            selectedCategoryID: 1,
            selectedGroupKeys: ["NL"]
        )

        state.retainSelections(availableIn: categories)

        #expect(state.selectedCategoryID == nil)
        #expect(state.selectedGroupKeys == ["NL"])
    }

    @Test func categorySelectionSurvivesWhenNoGroupIsSelected() {
        let categories = [
            makeCategory(id: 1, title: "|EN| Action"),
            makeCategory(id: 2, title: "|NL| Drama"),
        ]
        var state = LibraryFilterState(selectedCategoryID: 1)

        state.retainSelections(availableIn: categories)

        #expect(state.selectedCategoryID == 1)
        #expect(state.selectedGroupKeys.isEmpty)
    }

    @Test func categoryOptionsPreserveOrderAndIncludeExplicitUngroupedSelection() {
        let categories = [
            makeCategory(id: 1, title: "|EN| Action"),
            makeCategory(id: 2, title: "|NL| Drama"),
            makeCategory(id: 3, title: "Kids"),
            makeCategory(id: 4, title: "|EN| Comedy"),
        ]

        let selectedOptions = LibraryCategoryFilterOptions.categories(
            categories,
            matchingGroupKeys: ["NL", CategoryGrouping.ungroupedKey]
        )
        let allOptions = LibraryCategoryFilterOptions.categories(
            categories,
            matchingGroupKeys: []
        )

        #expect(selectedOptions.map(\.id) == [2, 3])
        #expect(allOptions.map(\.id) == [1, 2, 3, 4])
    }

    @Test func scopeVisibleCoverageRemainsPartialForNonemptyAndZeroMatchResults() {
        let categories = [
            makeCategory(id: 1, type: .movie, title: "|EN| Visible"),
            makeCategory(id: 2, type: .movie, title: "|NL| Hidden"),
            makeCategory(id: 3, type: .series, title: "|EN| Out of Scope"),
        ]
        let media = [
            makeMedia(id: 1, sourceID: 100, type: .movie, title: "Alpha", categoryID: 1),
            makeMedia(id: 2, sourceID: 101, type: .movie, title: "Beta", categoryID: 2),
        ]
        let projection = LibraryCategoryProjection(
            categories: categories,
            hiddenGroupKeys: ["NL"],
            includedTypes: LibrarySearchScope.movies.includedTypes
        )
        let hydration = LibraryHydrationSnapshot(
            categories: categories,
            media: media,
            overrides: [
                1: .loading,
                2: .failed("Hidden failure"),
                3: .unhydrated,
            ]
        )
        let coverage = hydration.coverage(for: projection.selectableCategories)

        let nonemptyResults = LibraryFilterEngine.filteredMedia(
            media,
            categories: categories,
            state: LibraryFilterState(),
            hiddenGroupKeys: ["NL"],
            query: "Alpha"
        )
        let zeroMatchResults = LibraryFilterEngine.filteredMedia(
            media,
            categories: categories,
            state: LibraryFilterState(),
            hiddenGroupKeys: ["NL"],
            query: "Missing"
        )

        #expect(nonemptyResults.map(\.sourceID) == [100])
        #expect(zeroMatchResults.isEmpty)
        #expect(coverage == LibraryHydrationCoverage(states: [.loading]))
        #expect(coverage.message != nil)
    }

    @Test func emptyCriteriaDistinguishQueryFiltersAndCombinedRecovery() {
        #expect(LibraryEmptyCriteria(query: "", filterState: LibraryFilterState()) == .none)
        #expect(LibraryEmptyCriteria(query: "Alpha", filterState: LibraryFilterState()) == .queryOnly)
        #expect(
            LibraryEmptyCriteria(
                query: "",
                filterState: LibraryFilterState(selectedGroupKeys: ["EN"])
            ) == .filtersOnly
        )
        #expect(
            LibraryEmptyCriteria(
                query: "Alpha",
                filterState: LibraryFilterState(minimumRating: 8)
            ) == .queryAndFilters
        )
    }

    @Test func visibilityCacheLoadsOnceForProviderRevisionAndInvalidatesOnRevision() {
        var cache = CategoryPrefixVisibilityCache()
        var loadCount = 0
        let firstRequest = CategoryPrefixVisibilityRequest(providerID: 1, revision: 4)

        let first = cache.resolve(firstRequest) {
            loadCount += 1
            return CategoryPrefixVisibilitySnapshot(request: firstRequest, hiddenGroupKeys: ["NL"])
        }
        let repeated = cache.resolve(firstRequest) {
            loadCount += 1
            return CategoryPrefixVisibilitySnapshot(request: firstRequest, hiddenGroupKeys: ["EN"])
        }

        let nextRequest = CategoryPrefixVisibilityRequest(providerID: 1, revision: 5)
        let revised = cache.resolve(nextRequest) {
            loadCount += 1
            return CategoryPrefixVisibilitySnapshot(request: nextRequest, hiddenGroupKeys: ["EN"])
        }

        #expect(first.hiddenGroupKeys == ["NL"])
        #expect(repeated.hiddenGroupKeys == ["NL"])
        #expect(revised.hiddenGroupKeys == ["EN"])
        #expect(loadCount == 2)
    }

    @Test func searchIndexesProvideConstantTimeCategoryFavoriteAndActivityLookups() {
        let providerID = 7
        let category = makeCategory(id: 1, title: "|EN| Movies")
        let media = makeMedia(id: 1, sourceID: 100, title: "Alpha", categoryID: category.id)
        let favorite = Favorite(
            id: 1,
            profileID: UserProfileStore.primaryProfileID,
            providerID: providerID,
            mediaType: .movie,
            sourceID: media.sourceID,
            title: media.title,
            artworkURL: nil,
            categoryID: category.id,
            categoryTitle: category.title
        )
        let activity = WatchActivity(
            id: 1,
            profileID: UserProfileStore.primaryProfileID,
            providerID: providerID,
            mediaType: .movie,
            sourceID: media.sourceID,
            title: media.title,
            artworkURL: nil,
            categoryTitle: category.title,
            currentTime: 60,
            duration: 300,
            completed: false
        )

        let indexes = LibrarySearchIndexes(
            providerID: providerID,
            categories: [category],
            favorites: [favorite],
            watchActivities: [activity]
        )

        #expect(indexes.category(for: media) == category)
        #expect(indexes.isFavorite(media))
        #expect(indexes.watchActivity(for: media) == activity)
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

    @Test func crossTypeSortTiesAreStrictAndIndependentOfInputOrder() {
        let movie = makeMedia(
            id: 20,
            sourceID: 100,
            type: .movie,
            title: "Same",
            rating: 8,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let series = makeMedia(
            id: 10,
            sourceID: 100,
            type: .series,
            title: "Same",
            rating: 8,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        for sort in BrowseSort.allCases {
            let state = LibraryFilterState(sort: sort)
            let forward = LibraryFilterEngine.filteredMedia(
                [movie, series],
                categories: [],
                state: state
            )
            let reversed = LibraryFilterEngine.filteredMedia(
                [series, movie],
                categories: [],
                state: state
            )

            #expect(forward.map(\.type) == [.movie, .series])
            #expect(reversed.map(\.type) == [.movie, .series])
        }
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
        let database = try testAppDatabase()
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
                    credentialReference: "library-filter-\(UUID().uuidString)",
                    endpoint: endpoint,
                    allowsInsecureHTTP: false,
                    isActive: false
                )
            }
            .returning(\.self)
            .fetchOne(db)!
            providerID = provider.id
        }

        return try #require(providerID)
    }


    private func makeCategory(
        id: iptv.Category.ID,
        type: MediaType = .movie,
        title: String,
        updatedAt: Date? = nil
    ) -> iptv.Category {
        iptv.Category(
            id: id,
            sourceID: "category-\(id)",
            type: type,
            title: title,
            groupKey: CategoryGrouping.key(for: title),
            updatedAt: updatedAt
        )
    }

    private func makeMedia(
        id: iptv.Media.ID,
        sourceID: Int,
        type: MediaType = .movie,
        title: String,
        categoryID: iptv.Category.ID? = nil,
        rating: Double? = nil,
        updatedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> iptv.Media {
        iptv.Media(
            id: id,
            sourceID: sourceID,
            type: type,
            title: title,
            categoryID: categoryID,
            tmdbID: nil,
            coverURL: nil,
            rating: rating,
            updatedAt: updatedAt
        )
    }
}
