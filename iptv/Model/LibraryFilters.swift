import Dependencies
import Foundation
import SQLiteData

/// Deterministic sort options supported by local catalog browse and search surfaces.
enum BrowseSort: String, CaseIterable, Identifiable, Sendable {
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
enum CategoryGrouping: Sendable {
    static let ungroupedKey = "---"

    /// Extracts a provider prefix/group key from a category title.
    ///
    /// Pipe-delimited names such as `|NL| Movies` use the first pipe segment as the group key.
    /// Categories without that shape remain in the ungrouped bucket.
    static func key(for title: String) -> String {
        if let match = title.firstMatch(of: #/\|([^|]+)\|\s*(.*)/#) {
            let key = String(match.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? ungroupedKey : key
        }

        return ungroupedKey
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
enum LibraryQueryNormalizer: Sendable {
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
struct LibraryFilterState: Hashable, Sendable {
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
    }
}

/// Pure local filtering and sorting helpers for catalog media.
enum LibraryFilterEngine: Sendable {
    /// Returns media that match all active filter groups, sorted with deterministic tie-breakers.
    static func filteredMedia(
        _ media: [Media],
        categories: [Category],
        state: LibraryFilterState,
        hiddenGroupKeys: Set<String> = [],
        query: String = ""
    ) -> [Media] {
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        return media
            .filter { matches($0, categoryByID: categoryByID, state: state, hiddenGroupKeys: hiddenGroupKeys, query: query) }
            .sorted { ordered($0, before: $1, by: state.sort) }
    }

    /// Evaluates AND-across-groups / OR-within-group filter semantics for one media row.
    static func matches(
        _ media: Media,
        categoryByID: [Category.ID: Category],
        state: LibraryFilterState,
        hiddenGroupKeys: Set<String> = [],
        query: String = ""
    ) -> Bool {
        let category = media.categoryID.flatMap { categoryByID[$0] }
        let groupKey = category.map { CategoryGrouping.key(for: $0.title) } ?? CategoryGrouping.ungroupedKey

        if hiddenGroupKeys.contains(groupKey) {
            return false
        }

        if let selectedCategoryID = state.selectedCategoryID, media.categoryID != selectedCategoryID {
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

        if !LibraryQueryNormalizer.matches(media.title, query: query) {
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

        return lhs.sourceID < rhs.sourceID
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
            assertionFailure("Failed to load category prefix visibility: \(error.localizedDescription)")
            return []
        }
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
            assertionFailure("Failed to save category prefix visibility: \(error.localizedDescription)")
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
