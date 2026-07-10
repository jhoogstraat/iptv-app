//
//  SearchScreen.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import SwiftUI
import SQLiteData

struct SearchScreen: View {

    @AppStorage(CategoryPrefixVisibilityStore.revisionKey) private var prefixVisibilityRevision = 0
    @State private var prefixVisibilityCache = CategoryPrefixVisibilityCache()
    @Environment(Session.self) private var session
    @FetchAll(Category.where { $0.type.eq(MediaType.movie).or($0.type.eq(MediaType.series)) }) private var categories: [Category]
    @FetchAll(Media.where { $0.type.eq(MediaType.movie).or($0.type.eq(MediaType.series)) }) private var media: [Media]
    @FetchAll private var favorites: [Favorite]
    @FetchAll private var watchActivities: [WatchActivity]

    @State private var searchText = ""
    @State private var selectedCategoryID: Category.ID?
    @State private var selectedGroupKeys: Set<String> = []
    @State private var minimumRating: Double?
    @State private var sort: BrowseSort = .title
    @State private var scope: LibrarySearchScope = .all

    private var visibilityRequest: CategoryPrefixVisibilityRequest {
        CategoryPrefixVisibilityRequest(
            providerID: session.providerID,
            revision: prefixVisibilityRevision
        )
    }

    private var visibilitySnapshot: CategoryPrefixVisibilitySnapshot? {
        prefixVisibilityCache.snapshot(for: visibilityRequest)
    }

    private var hiddenGroupKeys: Set<String> {
        visibilitySnapshot?.hiddenGroupKeys ?? []
    }

    private var categoryProjection: LibraryCategoryProjection {
        LibraryCategoryProjection(
            categories: categories,
            hiddenGroupKeys: hiddenGroupKeys,
            includedTypes: scope.includedTypes
        )
    }

    private var visibleCategories: [Category] {
        categoryProjection.selectableCategories
    }

    private var hydrationSnapshot: LibraryHydrationSnapshot {
        LibraryHydrationSnapshot(
            categories: categories,
            media: media,
            overrides: session.runtimeHydrationStates
        )
    }

    private var visibleHydrationCoverage: LibraryHydrationCoverage {
        hydrationSnapshot.coverage(for: visibleCategories)
    }

    private var scopedMedia: [Media] {
        media.filter { scope.includes($0.type) }
    }

    private var filterState: LibraryFilterState {
        LibraryFilterState(
            selectedCategoryID: selectedCategoryID,
            selectedGroupKeys: selectedGroupKeys,
            minimumRating: minimumRating,
            sort: sort
        )
    }

    private var searchIsActive: Bool {
        !LibraryQueryNormalizer.isEmpty(searchText) || filterState.hasActiveFilters
    }

    private var results: [Media] {
        LibraryFilterEngine.filteredMedia(
            scopedMedia,
            categories: categories,
            state: filterState,
            hiddenGroupKeys: hiddenGroupKeys,
            query: searchText
        )
    }

    var body: some View {
        let indexes = LibrarySearchIndexes(
            providerID: session.providerID,
            categories: categories,
            favorites: favorites,
            watchActivities: watchActivities
        )
        let projectedResults = results

        NavigationStack {
            VStack(spacing: 0) {
                if visibilitySnapshot != nil, !categories.isEmpty {
                    LibraryFilterBar(
                        categories: visibleCategories,
                        state: Binding(
                            get: { filterState },
                            set: apply
                        ),
                        clearFilters: clearFilters
                    )
                    Divider()
                }

                Picker("Scope", selection: $scope) {
                    ForEach(LibrarySearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                content(indexes: indexes, results: projectedResults)
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search Movies and Series")
            .task(id: visibilityRequest) {
                prefixVisibilityCache.resolve(visibilityRequest) {
                    CategoryPrefixVisibilityStore.snapshot(for: visibilityRequest)
                }
            }
            .onChange(of: scope) { _, _ in
                retainScopeCompatibleSelections()
            }
            .onChange(of: categoryProjection.selectableCategoryIDs) { _, _ in
                retainScopeCompatibleSelections()
            }
        }
    }

    private func content(indexes: LibrarySearchIndexes, results: [Media]) -> some View {
        Group {
            if visibilitySnapshot == nil {
                ProgressView("Loading category visibility")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if categories.filter({ scope.includes($0.type) }).isEmpty {
                ContentUnavailableView {
                    Label("No searchable \(scope.title.lowercased()) library", systemImage: "magnifyingglass")
                } description: {
                    Text("Sync \(scope.title == "All" ? "Movies or Series" : scope.title) before searching.")
                }
            } else if visibleCategories.isEmpty {
                ContentUnavailableView {
                    Label("All category groups hidden", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Clear prefix visibility settings to search the \(scope.title.lowercased()) library.")
                } actions: {
                    Button("Clear Prefix Visibility") {
                        CategoryPrefixVisibilityStore.setHiddenGroupKeys([], for: session.providerID)
                    }
                }
            } else {
                searchExperience(indexes: indexes, results: results)
            }
        }
    }

    private func searchExperience(indexes: LibrarySearchIndexes, results: [Media]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = visibleHydrationCoverage.message {
                Label(message, systemImage: "externaldrive.badge.questionmark")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

            if !searchIsActive {
                if scopedMedia.isEmpty {
                    ContentUnavailableView {
                        Label("No local \(scope.title.lowercased()) streams loaded", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("Open a category in Browse to load streams into the local library.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("Search your library", systemImage: "magnifyingglass")
                    } description: {
                        Text("Search local Movies and Series, then narrow results with category group, category, rating, and sort filters.")
                    }
                }
            } else if results.isEmpty {
                emptyResults
            } else {
                List(results) { media in
                    NavigationLink {
                        MediaDetailDestination(media: media, categoryTitle: indexes.category(for: media)?.title)
                    } label: {
                        SearchResultRow(
                            media: media,
                            category: indexes.category(for: media),
                            isFavorite: indexes.isFavorite(media),
                            watchActivity: indexes.watchActivity(for: media)
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var emptyResults: some View {
        switch LibraryEmptyCriteria(query: searchText, filterState: filterState) {
        case .none:
            ContentUnavailableView("No local results", systemImage: "tray")
        case .queryOnly:
            ContentUnavailableView {
                Label("No titles match your search", systemImage: "magnifyingglass")
            } description: {
                Text("Try a different title or clear the search.")
            } actions: {
                Button("Clear Search") {
                    searchText = ""
                }
            }
        case .filtersOnly:
            ContentUnavailableView {
                Label("No titles match these filters", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Clear the category, group, or rating filters to broaden the local results.")
            } actions: {
                Button("Clear Filters", action: clearFilters)
            }
        case .queryAndFilters:
            ContentUnavailableView {
                Label("No titles match your search and filters", systemImage: "magnifyingglass")
            } description: {
                Text("Clear the search and filters to show all locally available titles.")
            } actions: {
                Button("Clear Search and Filters") {
                    clearFilters()
                    searchText = ""
                }
            }
        }
    }


    private func clearFilters() {
        var nextState = filterState
        nextState.clearFilters()
        apply(nextState)
    }

    private func retainScopeCompatibleSelections() {
        var nextState = filterState
        nextState.retainSelections(availableIn: visibleCategories)
        apply(nextState)
    }

    private func apply(_ state: LibraryFilterState) {
        selectedCategoryID = state.selectedCategoryID
        selectedGroupKeys = state.selectedGroupKeys
        minimumRating = state.minimumRating
        sort = state.sort
    }

}

private struct SearchResultRow: View {
    let media: Media
    let category: Category?
    let isFavorite: Bool
    let watchActivity: WatchActivity?
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

                HStack(spacing: 8) {
                    if isFavorite {
                        Label("Favorite", systemImage: "heart.fill")
                            .foregroundStyle(.red)
                    }

                    if let watchActivity {
                        Label("\(formatDuration(watchActivity.currentTime)) watched", systemImage: "play.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

#Preview {
    SearchScreen()
}
