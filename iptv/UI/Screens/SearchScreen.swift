//
//  SearchScreen.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import SwiftUI
import SQLiteData

struct SearchScreen: View {
    private enum SearchScope: String, CaseIterable, Identifiable {
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

        func includes(_ type: MediaType) -> Bool {
            switch self {
            case .all:
                type == .movie || type == .series
            case .movies:
                type == .movie
            case .series:
                type == .series
            }
        }
    }

    @AppStorage(CategoryPrefixVisibilityStore.revisionKey) private var prefixVisibilityRevision = 0
    @Environment(Session.self) private var session
    @FetchOne(Provider.where(\.isActive)) private var provider: Provider?
    @FetchAll(Category.where { $0.type.eq(MediaType.movie).or($0.type.eq(MediaType.series)) }) private var categories: [Category]
    @FetchAll(Media.where { $0.type.eq(MediaType.movie).or($0.type.eq(MediaType.series)) }) private var media: [Media]

    @State private var searchText = ""
    @State private var selectedCategoryID: Category.ID?
    @State private var selectedGroupKeys: Set<String> = []
    @State private var minimumRating: Double?
    @State private var sort: BrowseSort = .title
    @State private var scope: SearchScope = .all

    private var hiddenGroupKeys: Set<String> {
        _ = prefixVisibilityRevision
        return CategoryPrefixVisibilityStore.hiddenGroupKeys(for: provider?.id)
    }

    private var visibleCategories: [Category] {
        categories
            .filter { !hiddenGroupKeys.contains(CategoryGrouping.key(for: $0.title)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var visibleCategoryIDs: [Category.ID] {
        visibleCategories.map(\.id)
    }

    private var visibleGroupKeys: Set<String> {
        Set(visibleCategories.map { CategoryGrouping.key(for: $0.title) })
    }

    private var filterState: LibraryFilterState {
        LibraryFilterState(
            selectedCategoryID: selectedCategoryID,
            selectedGroupKeys: selectedGroupKeys,
            minimumRating: minimumRating,
            sort: sort
        )
    }

    private var categoryHydrationStates: [SyncManager.CategoryHydrationState] {
        categories.map { session.hydrationState(for: $0) }
    }

    private var hasUnhydratedCategories: Bool {
        categoryHydrationStates.contains(.unhydrated)
    }

    private var hasLoadingCategories: Bool {
        categoryHydrationStates.contains(.loading)
    }

    private var hasFailedCategories: Bool {
        categoryHydrationStates.contains { state in
            if case .failed = state { return true }
            return false
        }
    }

    private var searchIsActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filterState.hasActiveFilters
    }

    private var results: [Media] {
        let scopedMedia = media.filter { item in
            guard scope.includes(item.type) else { return false }
            guard !searchText.isEmpty else { return true }
            return item.title.localizedStandardContains(searchText)
        }

        return LibraryFilterEngine.filteredMedia(
            scopedMedia,
            categories: visibleCategories,
            state: filterState,
            hiddenGroupKeys: hiddenGroupKeys
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !categories.isEmpty {
                    LibraryFilterBar(
                        categories: visibleCategories,
                        state: Binding(
                            get: { filterState },
                            set: { nextState in
                                selectedCategoryID = nextState.selectedCategoryID
                                selectedGroupKeys = nextState.selectedGroupKeys
                                minimumRating = nextState.minimumRating
                                sort = nextState.sort
                            }
                        ),
                        clearFilters: clearFilters
                    )
                    Divider()
                }

                Picker("Scope", selection: $scope) {
                    ForEach(SearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                content
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search Movies and Series")
            .onChange(of: visibleCategoryIDs) { _, ids in
                if let selectedCategoryID, !ids.contains(selectedCategoryID) {
                    self.selectedCategoryID = nil
                }

                selectedGroupKeys = selectedGroupKeys.intersection(visibleGroupKeys)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if categories.isEmpty {
            ContentUnavailableView {
                Label("No searchable library", systemImage: "magnifyingglass")
            } description: {
                Text("Sync Movies or Series before searching.")
            }
        } else if visibleCategories.isEmpty {
            ContentUnavailableView {
                Label("All category groups hidden", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Clear prefix visibility settings to search the local library.")
            } actions: {
                Button("Clear Prefix Visibility") {
                    CategoryPrefixVisibilityStore.setHiddenGroupKeys([], for: provider?.id)
                }
            }
        } else if media.isEmpty {
            ContentUnavailableView {
                Label(emptyHydrationTitle, systemImage: emptyHydrationSystemImage)
            } description: {
                Text(emptyHydrationDescription)
            }
        } else if !searchIsActive {
            ContentUnavailableView {
                Label("Search your library", systemImage: "magnifyingglass")
            } description: {
                Text("Search local Movies and Series, then narrow results with category group, category, rating, and sort filters.")
            }
        } else if results.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(results) { media in
                NavigationLink {
                    MediaDetailDestination(media: media, categoryTitle: category(for: media)?.title)
                } label: {
                    SearchResultRow(media: media, category: category(for: media))
                }
            }
            .listStyle(.plain)
        }
    }

    private func category(for media: Media) -> Category? {
        guard let categoryID = media.categoryID else { return nil }
        return categories.first { $0.id == categoryID }
    }

    private func clearFilters() {
        selectedCategoryID = nil
        selectedGroupKeys.removeAll()
        minimumRating = nil
    }

    private var emptyHydrationTitle: String {
        if hasLoadingCategories { return "Loading category streams" }
        if hasFailedCategories { return "Some categories failed to load" }
        if hasUnhydratedCategories { return "No hydrated categories" }
        return "No searchable streams"
    }

    private var emptyHydrationSystemImage: String {
        if hasLoadingCategories { return "clock.arrow.circlepath" }
        if hasFailedCategories { return "exclamationmark.triangle" }
        if hasUnhydratedCategories { return "folder.badge.questionmark" }
        return "tray"
    }

    private var emptyHydrationDescription: String {
        if hasLoadingCategories {
            return "Search results will appear after the selected category finishes loading."
        }
        if hasFailedCategories {
            return "Retry the failed category from Browse, then search the local library again."
        }
        if hasUnhydratedCategories {
            return "Initial sync stores categories only. Open a category in Browse to lazily load its streams into the local library."
        }
        return "The hydrated categories did not contain any Movies or Series streams."
    }
}

private struct SearchResultRow: View {
    let media: Media
    let category: Category?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: media.coverURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(Color.secondary.opacity(0.16))
                        Image(systemName: media.type == .movie ? "film" : "tv")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 48, height: 72)
            .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(media.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(media.type == .movie ? "Movie" : "Series")

                    if let category {
                        Text("•")
                        Text(category.title)
                            .lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let rating = media.rating {
                    Label(rating.formatted(), systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SearchScreen()
}
