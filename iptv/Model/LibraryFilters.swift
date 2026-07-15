import Dependencies
import Foundation
import GRDB
import OSLog
import SQLiteData

/// Deterministic sort options supported by local catalog browse and search surfaces.
nonisolated enum BrowseSort: String, CaseIterable, Identifiable, Sendable {
    case title
    case newest
    case rating

    var id: Self { self }

    /// User-facing title for menus and filter pills.
    var title: String {
        switch self {
        case .title: "Title"
        case .newest: "Newest"
        case .rating: "Rating"
        }
    }

    /// Short label for compact filter controls.
    var compactTitle: String {
        switch self {
        case .title: "Title"
        case .newest: "Newest"
        case .rating: "Top Rated"
        }
    }

    /// System image that communicates the sorting direction.
    var systemImage: String {
        switch self {
        case .title: "textformat.abc"
        case .newest: "clock.arrow.circlepath"
        case .rating: "star.fill"
        }
    }
}

/// Provider-category grouping derived from the local category title.
///
/// The raw category title is kept intact. The grouping key is a local display/indexing aid only.
nonisolated enum CategoryGrouping: Sendable {
    static let ungroupedKey = "---"

    /// Extracts a provider prefix/group key from a category title.
    ///
    /// Pipe-delimited names such as `|NL| Movies` use the first pipe segment as the group key.
    /// Categories without that shape remain in the ungrouped bucket.
    static func key(for title: String) -> String {
        guard title.first == "|" else { return ungroupedKey }
        let remainder = title.dropFirst()
        guard let closingPipe = remainder.firstIndex(of: "|") else { return ungroupedKey }
        let key = remainder[..<closingPipe].trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? ungroupedKey : key
    }

    /// Display-safe title for a grouping key.
    static func title(for key: String) -> String {
        key == ungroupedKey ? "Ungrouped" : key
    }
}

/// Shared query normalization for local browse, search, and filter matching.
///
/// Normalization intentionally stays simple and deterministic: trim, lowercase, fold
/// diacritics/case/width, and collapse repeated whitespace.
nonisolated enum LibraryQueryNormalizer: Sendable {
    static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func isEmpty(_ value: String) -> Bool {
        normalized(value).isEmpty
    }

    static func matches(_ candidate: String, query: String) -> Bool {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return true }
        return normalized(candidate).contains(normalizedQuery)
    }
}

/// Local, composable filters shared by browse and search surfaces.
///
/// Semantics are AND across filter groups and OR within multi-select groups.
nonisolated struct LibraryFilterState: Hashable, Sendable {
    var selectedCategoryID: Category.ID?
    var selectedGroupKeys: Set<String>
    var minimumRating: Double?
    var sort: BrowseSort

    init(
        selectedCategoryID: Category.ID? = nil,
        selectedGroupKeys: Set<String> = [],
        minimumRating: Double? = nil,
        sort: BrowseSort = .title
    ) {
        self.selectedCategoryID = selectedCategoryID
        self.selectedGroupKeys = selectedGroupKeys
        self.minimumRating = minimumRating
        self.sort = sort
    }

    /// Number of user-visible filters that are currently constraining results.
    var activeFilterCount: Int {
        var count = 0
        if selectedCategoryID != nil { count += 1 }
        if !selectedGroupKeys.isEmpty { count += 1 }
        if minimumRating != nil { count += 1 }
        return count
    }

    var hasActiveFilters: Bool { activeFilterCount > 0 }

    mutating func clearFilters() {
        selectedCategoryID = nil
        selectedGroupKeys.removeAll()
        minimumRating = nil
        sort = .title
    }

    mutating func retainSelections(availableIn categories: [Category]) {
        let groupKeys = Set(categories.map(\.groupKey))
        selectedGroupKeys.formIntersection(groupKeys)

        guard let selectedCategoryID else { return }
        guard let selectedCategory = categories.first(where: { $0.id == selectedCategoryID }) else {
            self.selectedCategoryID = nil
            return
        }

        let selectedCategoryGroupKey = selectedCategory.groupKey
        if !selectedGroupKeys.isEmpty, !selectedGroupKeys.contains(selectedCategoryGroupKey) {
            self.selectedCategoryID = nil
        }
    }
}

nonisolated struct LibraryFilterRequest: Sendable {
    let media: [Media]
    let categories: [Category]
    let state: LibraryFilterState
    let hiddenGroupKeys: Set<String>
    let query: String
    let includedTypes: Set<MediaType>?

    init(
        media: [Media],
        categories: [Category],
        state: LibraryFilterState,
        hiddenGroupKeys: Set<String>,
        query: String,
        includedTypes: Set<MediaType>? = nil
    ) {
        self.media = media
        self.categories = categories
        self.state = state
        self.hiddenGroupKeys = hiddenGroupKeys
        self.query = query
        self.includedTypes = includedTypes
    }
}

/// Compact identity for a filter computation. Catalog rows intentionally stay out of this value:
/// SwiftUI compares task IDs on the main actor, so putting entire row arrays in the ID makes every
/// query change proportional to the size of the library before background work can begin.
nonisolated struct LibraryFilterTaskID: Hashable, Sendable {
    let state: LibraryFilterState
    let hiddenGroupKeys: Set<String>
    let normalizedQuery: String
    let includedTypes: Set<MediaType>?
    let catalogRevision: Int

    init(
        state: LibraryFilterState,
        hiddenGroupKeys: Set<String>,
        query: String,
        includedTypes: Set<MediaType>? = nil,
        catalogRevision: Int
    ) {
        self.state = state
        self.hiddenGroupKeys = hiddenGroupKeys
        self.normalizedQuery = LibraryQueryNormalizer.normalized(query)
        self.includedTypes = includedTypes
        self.catalogRevision = catalogRevision
    }
}

nonisolated enum LibraryEmptyCriteria: Equatable, Sendable {
    case none
    case queryOnly
    case filtersOnly
    case queryAndFilters

    init(query: String, filterState: LibraryFilterState) {
        let hasQuery = !LibraryQueryNormalizer.isEmpty(query)
        switch (hasQuery, filterState.hasActiveFilters) {
        case (false, false): self = .none
        case (true, false): self = .queryOnly
        case (false, true): self = .filtersOnly
        case (true, true): self = .queryAndFilters
        }
    }
}

/// A provider-visible category projection. The complete relationship map remains separate
/// from the selectable category list so hidden media never falls back to "Ungrouped".
struct LibraryCategoryProjection: Sendable {
    let categoryByID: [Category.ID: Category]
    let selectableCategories: [Category]
    let selectableCategoryIDs: Set<Category.ID>
    let selectableGroupKeys: Set<String>

    init(
        categories: [Category],
        hiddenGroupKeys: Set<String>,
        includedTypes: Set<MediaType>? = nil
    ) {
        categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        selectableCategories = categories
            .filter { category in
                let typeIsIncluded = includedTypes?.contains(category.type) ?? true
                return typeIsIncluded
                    && !hiddenGroupKeys.contains(category.groupKey)
            }
            .sorted { lhs, rhs in
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.id < rhs.id
            }
        selectableCategoryIDs = Set(selectableCategories.map(\.id))
        selectableGroupKeys = Set(selectableCategories.map(\.groupKey))
    }
}

nonisolated enum LibraryCategoryFilterOptions: Sendable {
    static func categories(
        _ categories: [Category],
        matchingGroupKeys: Set<String>
    ) -> [Category] {
        guard !matchingGroupKeys.isEmpty else { return categories }
        return categories.filter {
            matchingGroupKeys.contains($0.groupKey)
        }
    }

}

/// A compact observation used by category landing rows. Database changes only
/// publish this small dictionary instead of reducing the entire media catalog on
/// the main actor in every tab.
nonisolated struct LibraryMediaCountsRequest: FetchKeyRequest {
    struct Value: Equatable, Sendable {
        var byCategoryID: [Category.ID: Int] = [:]
    }

    let type: MediaType

    func fetch(_ db: Database) throws -> Value {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT categoryID, COUNT(*) AS mediaCount
            FROM media
            WHERE type = ? AND categoryID IS NOT NULL
            GROUP BY categoryID
            """,
            arguments: [type.rawValue]
        )
        return Value(
            byCategoryID: Dictionary(
                uniqueKeysWithValues: rows.map { row in
                    (row["categoryID"] as Int, row["mediaCount"] as Int)
                }
            )
        )
    }
}

enum LibrarySearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case movies
    case series

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .movies: "Movies"
        case .series: "Series"
        }
    }

    var includedTypes: Set<MediaType> {
        switch self {
        case .all: [.movie, .series]
        case .movies: [.movie]
        case .series: [.series]
        }
    }

    func includes(_ type: MediaType) -> Bool {
        includedTypes.contains(type)
    }
}

struct LibraryHydrationSnapshot: Sendable {
    let statesByCategoryID: [Category.ID: SyncManager.CategoryHydrationState]

    init(
        categories: [Category],
        media: [Media],
        overrides: [Category.ID: SyncManager.CategoryHydrationState] = [:]
    ) {
        self.init(
            categories: categories,
            mediaCountsByCategoryID: Self.mediaCountsByCategoryID(for: media),
            overrides: overrides
        )
    }

    init(
        categories: [Category],
        mediaCountsByCategoryID: [Category.ID: Int],
        overrides: [Category.ID: SyncManager.CategoryHydrationState] = [:]
    ) {
        statesByCategoryID = Dictionary(
            uniqueKeysWithValues: categories.map { category in
                let state: SyncManager.CategoryHydrationState
                if let override = overrides[category.id] {
                    state = override
                } else if category.updatedAt == nil {
                    state = .unhydrated
                } else {
                    let count = mediaCountsByCategoryID[category.id, default: 0]
                    state = count == 0 ? .empty : .populated(count)
                }
                return (category.id, state)
            }
        )
    }

    static func mediaCountsByCategoryID(for media: [Media]) -> [Category.ID: Int] {
        media.reduce(into: [Category.ID: Int]()) { counts, item in
            guard let categoryID = item.categoryID else { return }
            counts[categoryID, default: 0] += 1
        }
    }

    func state(for category: Category?) -> SyncManager.CategoryHydrationState {
        guard let category else { return .populated(0) }
        return statesByCategoryID[category.id] ?? .unhydrated
    }

    func coverage(for categories: [Category]) -> LibraryHydrationCoverage {
        LibraryHydrationCoverage(
            states: categories.map { statesByCategoryID[$0.id] ?? .unhydrated }
        )
    }
}

nonisolated struct LibraryHydrationCoverage: Equatable, Sendable {
    let loadingCount: Int
    let unhydratedCount: Int
    let failedCount: Int

    init(states: [SyncManager.CategoryHydrationState]) {
        loadingCount = states.filter { $0 == .loading }.count
        unhydratedCount = states.filter { $0 == .unhydrated }.count
        failedCount = states.filter {
            if case .failed = $0 { return true }
            return false
        }.count
    }

    var isPartial: Bool {
        loadingCount > 0 || unhydratedCount > 0 || failedCount > 0
    }

    var message: String? {
        guard isPartial else { return nil }

        var parts: [String] = []
        if loadingCount > 0 {
            parts.append("\(loadingCount) \(loadingCount == 1 ? "category is" : "categories are") loading")
        }
        if unhydratedCount > 0 {
            parts.append("\(unhydratedCount) \(unhydratedCount == 1 ? "category has" : "categories have") not been opened")
        }
        if failedCount > 0 {
            parts.append("\(failedCount) \(failedCount == 1 ? "category failed" : "categories failed") to load")
        }
        return "\(parts.joined(separator: "; ")); results are local and may be partial."
    }
}

struct LibraryContentKey: Hashable, Sendable {
    let mediaType: MediaType
    let sourceID: Int

    init(mediaType: MediaType, sourceID: Int) {
        self.mediaType = mediaType
        self.sourceID = sourceID
    }

    init(media: Media) {
        self.init(mediaType: media.type, sourceID: media.sourceID)
    }
}

struct LibrarySearchIndexes: Sendable {
    let categoryByID: [Category.ID: Category]
    let favoriteContentKeys: Set<LibraryContentKey>
    let resumableActivityByContentKey: [LibraryContentKey: WatchActivity]

    init(
        providerID: Provider.ID,
        profileID: UserProfile.ID = UserProfileStore.primaryProfileID,
        categories: [Category],
        favorites: [Favorite],
        watchActivities: [WatchActivity]
    ) {
        categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        favoriteContentKeys = Set(
            favorites.lazy
                .filter { $0.profileID == profileID && $0.providerID == providerID }
                .map { LibraryContentKey(mediaType: $0.mediaType, sourceID: $0.sourceID) }
        )

        resumableActivityByContentKey = watchActivities.reduce(into: [:]) { index, activity in
            guard activity.profileID == profileID,
                  activity.providerID == providerID,
                  activity.isResumeEligible
            else { return }
            let key = LibraryContentKey(mediaType: activity.mediaType, sourceID: activity.sourceID)
            if let existing = index[key], existing.lastWatchedAt >= activity.lastWatchedAt {
                return
            }
            index[key] = activity
        }
    }

    func category(for media: Media) -> Category? {
        media.categoryID.flatMap { categoryByID[$0] }
    }

    func isFavorite(_ media: Media) -> Bool {
        favoriteContentKeys.contains(LibraryContentKey(media: media))
    }

    func watchActivity(for media: Media) -> WatchActivity? {
        resumableActivityByContentKey[LibraryContentKey(media: media)]
    }
}

/// Pure local filtering and sorting helpers for catalog media.
nonisolated enum LibraryFilterEngine: Sendable {
    /// Returns media that match all active filter groups, sorted with deterministic tie-breakers.
    static func filteredMedia(
        _ media: [Media],
        categories: [Category],
        state: LibraryFilterState,
        hiddenGroupKeys: Set<String> = [],
        query: String = "",
        includedTypes: Set<MediaType>? = nil
    ) -> [Media] {
        let groupKeyByCategoryID = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, $0.groupKey) }
        )
        let normalizedQuery = LibraryQueryNormalizer.normalized(query)
        var result: [Media] = []
        result.reserveCapacity(media.count)

        for (index, item) in media.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled {
                return []
            }
            let groupKey = item.categoryID.flatMap { groupKeyByCategoryID[$0] }
                ?? CategoryGrouping.ungroupedKey
            guard matches(
                item,
                groupKey: groupKey,
                state: state,
                hiddenGroupKeys: hiddenGroupKeys,
                normalizedQuery: normalizedQuery,
                includedTypes: includedTypes
            ) else { continue }
            result.append(item)
        }

        guard !Task.isCancelled else { return [] }
        result.sort { ordered($0, before: $1, by: state.sort) }
        return Task.isCancelled ? [] : result
    }

    static func filteredMedia(inBackground request: LibraryFilterRequest) async -> [Media] {
        let worker = Task.detached(priority: .userInitiated) {
            filteredMedia(
                request.media,
                categories: request.categories,
                state: request.state,
                hiddenGroupKeys: request.hiddenGroupKeys,
                query: request.query,
                includedTypes: request.includedTypes
            )
        }

        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Evaluates AND-across-groups / OR-within-group filter semantics for one media row.
    static func matches(
        _ media: Media,
        categoryByID: [Category.ID: Category],
        state: LibraryFilterState,
        hiddenGroupKeys: Set<String> = [],
        query: String = ""
    ) -> Bool {
        let groupKey = media.categoryID.flatMap { categoryByID[$0]?.groupKey }
            ?? CategoryGrouping.ungroupedKey
        return matches(
            media,
            groupKey: groupKey,
            state: state,
            hiddenGroupKeys: hiddenGroupKeys,
            normalizedQuery: LibraryQueryNormalizer.normalized(query)
        )
    }

    private static func matches(
        _ media: Media,
        groupKey: String,
        state: LibraryFilterState,
        hiddenGroupKeys: Set<String>,
        normalizedQuery: String,
        includedTypes: Set<MediaType>? = nil
    ) -> Bool {
        if let includedTypes, !includedTypes.contains(media.type) {
            return false
        }

        if let selectedCategoryID = state.selectedCategoryID, media.categoryID != selectedCategoryID {
            return false
        }

        if hiddenGroupKeys.contains(groupKey) {
            return false
        }

        if !state.selectedGroupKeys.isEmpty, !state.selectedGroupKeys.contains(groupKey) {
            return false
        }

        if let minimumRating = state.minimumRating {
            guard let rating = media.rating, rating >= minimumRating else {
                return false
            }
        }

        if !normalizedQuery.isEmpty,
           !LibraryQueryNormalizer.normalized(media.title).contains(normalizedQuery) {
            return false
        }

        return true
    }

    /// Compares two media rows using the chosen sort and deterministic tie-breakers.
    static func ordered(_ lhs: Media, before rhs: Media, by sort: BrowseSort) -> Bool {
        switch sort {
        case .title:
            return titleThenSourceID(lhs, rhs)
        case .newest:
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return titleThenSourceID(lhs, rhs)
        case .rating:
            switch (lhs.rating, rhs.rating) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return titleThenSourceID(lhs, rhs)
            }
        }
    }

    private static func titleThenSourceID(_ lhs: Media, _ rhs: Media) -> Bool {
        let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        if lhs.sourceID != rhs.sourceID {
            return lhs.sourceID < rhs.sourceID
        }

        if lhs.type != rhs.type {
            return lhs.type.rawValue < rhs.type.rawValue
        }

        return lhs.id < rhs.id
    }
}

struct CategoryPrefixVisibilityRequest: Hashable, Sendable {
    let providerID: Provider.ID?
    let revision: Int
}

struct CategoryPrefixVisibilitySnapshot: Equatable, Sendable {
    let request: CategoryPrefixVisibilityRequest
    let hiddenGroupKeys: Set<String>
}

struct CategoryPrefixVisibilityCache: Sendable {
    private(set) var cachedSnapshot: CategoryPrefixVisibilitySnapshot?

    func snapshot(for request: CategoryPrefixVisibilityRequest) -> CategoryPrefixVisibilitySnapshot? {
        guard cachedSnapshot?.request == request else { return nil }
        return cachedSnapshot
    }

    @discardableResult
    mutating func resolve(
        _ request: CategoryPrefixVisibilityRequest,
        load: () -> CategoryPrefixVisibilitySnapshot
    ) -> CategoryPrefixVisibilitySnapshot {
        if let snapshot = snapshot(for: request) {
            return snapshot
        }

        let snapshot = load()
        precondition(snapshot.request == request)
        cachedSnapshot = snapshot
        return snapshot
    }
}

/// Provider-scoped persistence for hidden category prefix/group keys.
///
/// The active catalog is a singleton local library, but organization preferences are
/// provider-owned settings. Persisting hidden groups in SQLite keeps browse/search
/// visibility from leaking across providers and allows provider deletion to cascade.
enum CategoryPrefixVisibilityStore: Sendable {
    static let revisionKey = "library.categoryPrefixVisibility.revision"

    static func hiddenGroupKeys(
        for providerID: Provider.ID?,
        database suppliedDatabase: (any DatabaseWriter)? = nil,
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        guard let providerID else { return [] }
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase

        do {
            try migrateLegacyDefaultsIfNeeded(for: providerID, database: database, defaults: defaults)
            return try database.read { db in
                Set(
                    try CategoryPrefixVisibility
                        .select(\.groupKey)
                        .where { $0.providerID.eq(providerID).and($0.isHidden.eq(true)) }
                        .fetchAll(db)
                )
            }
        } catch {
            logger.error("Failed to load category prefix visibility: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func snapshot(
        for request: CategoryPrefixVisibilityRequest,
        database: (any DatabaseWriter)? = nil,
        defaults: UserDefaults = .standard
    ) -> CategoryPrefixVisibilitySnapshot {
        CategoryPrefixVisibilitySnapshot(
            request: request,
            hiddenGroupKeys: hiddenGroupKeys(
                for: request.providerID,
                database: database,
                defaults: defaults
            )
        )
    }

    static func setHiddenGroupKeys(
        _ groupKeys: Set<String>,
        for providerID: Provider.ID?,
        database suppliedDatabase: (any DatabaseWriter)? = nil,
        defaults: UserDefaults = .standard
    ) {
        guard let providerID else { return }
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase

        do {
            try database.write { db in
                try CategoryPrefixVisibility
                    .where { $0.providerID.eq(providerID) }
                    .delete()
                    .execute(db)

                for groupKey in groupKeys.sorted() {
                    try CategoryPrefixVisibility.insert {
                        CategoryPrefixVisibility.Draft(
                            id: nil,
                            providerID: providerID,
                            groupKey: groupKey,
                            isHidden: true
                        )
                    }.execute(db)
                }
            }

            if let key = legacyStorageKey(for: providerID) {
                defaults.removeObject(forKey: key)
            }
            defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
        } catch {
            logger.error("Failed to save category prefix visibility: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func migrateLegacyDefaultsIfNeeded(
        for providerID: Provider.ID,
        database: any DatabaseWriter,
        defaults: UserDefaults
    ) throws {
        guard let key = legacyStorageKey(for: providerID),
              let legacyHiddenGroups = defaults.stringArray(forKey: key),
              !legacyHiddenGroups.isEmpty
        else { return }

        let existingCount = try database.read { db in
            try CategoryPrefixVisibility
                .where { $0.providerID.eq(providerID) }
                .fetchCount(db)
        }

        guard existingCount == 0 else { return }

        try database.write { db in
            for groupKey in Set(legacyHiddenGroups).sorted() {
                try CategoryPrefixVisibility.insert {
                    CategoryPrefixVisibility.Draft(
                        id: nil,
                        providerID: providerID,
                        groupKey: groupKey,
                        isHidden: true
                    )
                }.execute(db)
            }
        }

        defaults.removeObject(forKey: key)
        defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }

    private static func legacyStorageKey(for providerID: Provider.ID?) -> String? {
        guard let providerID else { return nil }
        return "library.categoryPrefixVisibility.provider.\(providerID).hiddenGroups"
    }
}

private let logger = Logger(subsystem: "IPTV", category: "LibraryFilters")
