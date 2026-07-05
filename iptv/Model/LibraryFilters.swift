import Foundation

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
        hiddenGroupKeys: Set<String> = []
    ) -> [Media] {
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        return media
            .filter { matches($0, categoryByID: categoryByID, state: state, hiddenGroupKeys: hiddenGroupKeys) }
            .sorted { ordered($0, before: $1, by: state.sort) }
    }

    /// Evaluates AND-across-groups / OR-within-group filter semantics for one media row.
    static func matches(
        _ media: Media,
        categoryByID: [Category.ID: Category],
        state: LibraryFilterState,
        hiddenGroupKeys: Set<String> = []
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
/// The active schema stores a single local library at a time, so prefix preferences are persisted
/// outside the library rows and keyed by provider identifier. This keeps preferences from leaking
/// when users switch configured providers.
enum CategoryPrefixVisibilityStore: Sendable {
    static let revisionKey = "library.categoryPrefixVisibility.revision"

    static func hiddenGroupKeys(for providerID: Provider.ID?, defaults: UserDefaults = .standard) -> Set<String> {
        guard let key = storageKey(for: providerID) else { return [] }
        return Set(defaults.stringArray(forKey: key) ?? [])
    }

    static func setHiddenGroupKeys(
        _ groupKeys: Set<String>,
        for providerID: Provider.ID?,
        defaults: UserDefaults = .standard
    ) {
        guard let key = storageKey(for: providerID) else { return }
        defaults.set(groupKeys.sorted(), forKey: key)
        defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }

    private static func storageKey(for providerID: Provider.ID?) -> String? {
        guard let providerID else { return nil }
        return "library.categoryPrefixVisibility.provider.\(providerID).hiddenGroups"
    }
}
