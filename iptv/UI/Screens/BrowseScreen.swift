//
//  MoviesScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import SQLiteData


struct BrowseScreen: View {
    let type: MediaType

    @Environment(Session.self) private var session
    @AppStorage(CategoryPrefixVisibilityStore.revisionKey) private var prefixVisibilityRevision = 0
    @State private var prefixVisibilityCache = CategoryPrefixVisibilityCache()
    @State private var selectedGroupKeys: Set<String> = []
    @State private var categorySearchText = ""

    @Fetch private var mediaCounts = LibraryMediaCountsRequest.Value()
    @FetchAll private var categories: [Category]

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
        LibraryCategoryProjection(categories: categories, hiddenGroupKeys: hiddenGroupKeys)
    }

    private var visibleCategories: [Category] {
        categoryProjection.selectableCategories
    }

    private var landingCategories: [Category] {
        let grouped = LibraryCategoryFilterOptions.categories(
            visibleCategories,
            matchingGroupKeys: selectedGroupKeys
        )
        guard !LibraryQueryNormalizer.isEmpty(categorySearchText) else { return grouped }
        return grouped.filter { LibraryQueryNormalizer.matches($0.displayTitle, query: categorySearchText) }
    }

    private var hydrationSnapshot: LibraryHydrationSnapshot {
        LibraryHydrationSnapshot(
            categories: categories,
            mediaCountsByCategoryID: mediaCounts.byCategoryID,
            overrides: session.runtimeHydrationStates
        )
    }

    private var screenTitle: String {
        switch type {
        case .movie:
            "Movies"
        case .series:
            "Series"
        default:
            "Content"
        }
    }

    private var filterState: LibraryFilterState {
        LibraryFilterState(
            selectedGroupKeys: selectedGroupKeys
        )
    }

    init(type: MediaType) {
        self.type = type
        self._categories = FetchAll(Category.where { $0.type.eq(type) })
        self._mediaCounts = Fetch(
            wrappedValue: LibraryMediaCountsRequest.Value(),
            LibraryMediaCountsRequest(type: type)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if visibilitySnapshot != nil, !categories.isEmpty {
                LibraryFilterBar(
                    categories: visibleCategories,
                    showsCategoryFilter: false,
                    showsRatingFilter: false,
                    showsSort: false,
                    state: Binding(
                        get: { filterState },
                        set: { selectedGroupKeys = $0.selectedGroupKeys }
                    ),
                    clearFilters: { selectedGroupKeys.removeAll() }
                )
                Divider()
            }

            content
        }
        .navigationTitle(screenTitle)
        .searchable(text: $categorySearchText, prompt: "Search categories")
        .compactSearchToolbar()
        .task(id: visibilityRequest) {
            prefixVisibilityCache.resolve(visibilityRequest) {
                CategoryPrefixVisibilityStore.snapshot(for: visibilityRequest)
            }
        }
        .onChange(of: categoryProjection.selectableCategoryIDs) { _, _ in
            let availableGroups = Set(visibleCategories.map(\.groupKey))
            selectedGroupKeys.formIntersection(availableGroups)
        }
    }

    @ViewBuilder
    private var content: some View {
        if visibilitySnapshot == nil {
            ProgressView("Loading category visibility")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if categories.isEmpty {
            ContentUnavailableView {
                Text("No \(screenTitle) available")
            } description: {
                Text("The configured provider did not return any \(screenTitle.lowercased()).")
            }
        } else if visibleCategories.isEmpty {
            ContentUnavailableView {
                Label("All category groups hidden", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Clear prefix visibility settings to show \(screenTitle.lowercased()).")
            } actions: {
                Button("Clear Prefix Visibility") {
                    CategoryPrefixVisibilityStore.setHiddenGroupKeys([], for: session.providerID)
                }
            }
        } else if landingCategories.isEmpty {
            ContentUnavailableView.search(text: categorySearchText)
        } else {
            LibraryCategoryList(
                categories: landingCategories,
                hydrationSnapshot: hydrationSnapshot,
                contentName: type == .series ? "series" : "movie"
            ) { category in
                BrowseCategoryScreen(type: type, category: category)
            }
        }
    }
}

private struct BrowseCategoryScreen: View {
    let type: MediaType
    let category: Category

    @Environment(Session.self) private var session
    @State private var searchText = ""
    @State private var sort: BrowseSort = .title
    @State private var minimumRating: Double?
    @Fetch private var mediaCounts = LibraryMediaCountsRequest.Value()
    @FetchAll private var media: [Media]

    init(type: MediaType, category: Category) {
        self.type = type
        self.category = category
        self._media = FetchAll(
            Media.where { $0.type.eq(type).and($0.categoryID.eq(category.id)) }
        )
        self._mediaCounts = Fetch(
            wrappedValue: LibraryMediaCountsRequest.Value(),
            LibraryMediaCountsRequest(type: type)
        )
    }

    private var filterState: LibraryFilterState {
        LibraryFilterState(
            selectedCategoryID: category.id,
            minimumRating: minimumRating,
            sort: sort
        )
    }

    private var hydrationState: SyncManager.CategoryHydrationState {
        LibraryHydrationSnapshot(
            categories: [category],
            mediaCountsByCategoryID: mediaCounts.byCategoryID,
            overrides: session.runtimeHydrationStates
        ).state(for: category)
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryFilterBar(
                categories: [category],
                showsCategoryFilter: false,
                showsGroupFilter: false,
                state: Binding(
                    get: { filterState },
                    set: apply
                ),
                clearFilters: clearFilters
            )
            Divider()

            CoverGridSection(
                type: type,
                filterState: filterState,
                filter: searchText,
                categories: [category],
                media: media,
                hiddenGroupKeys: [],
                selectedCategory: category,
                hydrationState: hydrationState,
                visibleHydrationCoverage: LibraryHydrationSnapshot(
                    categories: [category],
                    mediaCountsByCategoryID: mediaCounts.byCategoryID,
                    overrides: session.runtimeHydrationStates
                ).coverage(for: [category]),
                clearFilters: clearFilters,
                clearSearchAndFilters: clearSearchAndFilters,
                retryHydration: {
                    Task { await hydrate(force: true) }
                }
            )
        }
        .navigationTitle(category.displayTitle)
        .searchable(text: $searchText, prompt: "Search \(category.displayTitle)")
        .compactSearchToolbar()
        .task(id: category.id) {
            await hydrate(force: false)
        }
    }

    private func apply(_ state: LibraryFilterState) {
        minimumRating = state.minimumRating
        sort = state.sort
    }

    private func clearFilters() {
        minimumRating = nil
        sort = .title
    }

    private func clearSearchAndFilters() {
        clearFilters()
        searchText = ""
    }

    private func hydrate(force: Bool) async {
        if !force, hydrationState != .unhydrated { return }
        do {
            try await session.update(type, in: category.id)
        } catch {
            return
        }
    }
}

struct CoverGridSection: View {
    @AppStorage(UserProfileStore.revisionKey) private var profileRevision = 0
    let type: MediaType
    let filterState: LibraryFilterState
    let filter: String
    let categories: [Category]
    let media: [Media]
    let hiddenGroupKeys: Set<String>
    let selectedCategory: Category?
    let hydrationState: SyncManager.CategoryHydrationState
    let visibleHydrationCoverage: LibraryHydrationCoverage
    let clearFilters: () -> Void
    let clearSearchAndFilters: () -> Void
    let retryHydration: () -> Void
    @Environment(Session.self) private var session
    @FetchAll private var favorites: [Favorite]
    @FetchAll private var watchActivities: [WatchActivity]
    @State private var displayedMedia: [Media] = []
    @State private var hasCompletedInitialComputation = false
    @State private var catalogRevision = 0

    init(
        type: MediaType,
        filterState: LibraryFilterState,
        filter: String,
        categories: [Category],
        media: [Media],
        hiddenGroupKeys: Set<String>,
        selectedCategory: Category?,
        hydrationState: SyncManager.CategoryHydrationState,
        visibleHydrationCoverage: LibraryHydrationCoverage,
        clearFilters: @escaping () -> Void,
        clearSearchAndFilters: @escaping () -> Void,
        retryHydration: @escaping () -> Void
    ) {
        self.type = type
        self.filterState = filterState
        self.filter = filter
        self.categories = categories
        self.media = media
        self.hiddenGroupKeys = hiddenGroupKeys
        self.selectedCategory = selectedCategory
        self.hydrationState = hydrationState
        self.visibleHydrationCoverage = visibleHydrationCoverage
        self.clearFilters = clearFilters
        self.clearSearchAndFilters = clearSearchAndFilters
        self.retryHydration = retryHydration
    }

    private var request: LibraryFilterRequest {
        LibraryFilterRequest(
            media: media,
            categories: categories,
            state: filterState,
            hiddenGroupKeys: hiddenGroupKeys,
            query: filter,
            includedTypes: [type]
        )
    }

    private var taskID: LibraryFilterTaskID {
        LibraryFilterTaskID(
            state: filterState,
            hiddenGroupKeys: hiddenGroupKeys,
            query: filter,
            includedTypes: [type],
            catalogRevision: catalogRevision
        )
    }

    private var favoriteContentKeys: Set<String> {
        Set(
            favorites
                .filter { $0.profileID == session.activeProfileID && $0.providerID == session.providerID }
                .map { FavoriteStore.contentKey(mediaType: $0.mediaType, sourceID: $0.sourceID) }
        )
    }

    private var resumableContentKeys: Set<String> {
        Set(
            watchActivities
                .filter { $0.profileID == session.activeProfileID && $0.providerID == session.providerID && $0.isResumeEligible }
                .map { FavoriteStore.contentKey(mediaType: $0.mediaType, sourceID: $0.sourceID) }
        )
    }

    var body: some View {
        Group {
            if let selectedCategory {
                switch hydrationState {
                case .unhydrated, .loading:
                    BrowseLoadingGrid()
                case .empty:
                    ContentUnavailableView {
                        Label("No \(selectedCategory.title) items", systemImage: "tray")
                    } description: {
                        Text("The provider returned this category, but no streams were found for it.")
                    }
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Couldn’t load \(selectedCategory.title)", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry", action: retryHydration)
                    }
                case .populated:
                    populatedGrid
                }
            } else {
                populatedGrid
            }
        }
        .task(id: taskID) {
            let currentRequest = request
            if !taskID.normalizedQuery.isEmpty {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
            }
            let result = await LibraryFilterEngine.filteredMedia(inBackground: currentRequest)
            guard !Task.isCancelled else { return }

            displayedMedia = result
            hasCompletedInitialComputation = true
        }
        .onChange(of: categories) { _, _ in
            catalogRevision &+= 1
        }
        .task(id: media.count) {
            // Count changes are sufficient for hydration inserts/deletes and avoid
            // equality-comparing a potentially large media array on the main actor.
            catalogRevision &+= 1
        }
    }

    @ViewBuilder
    private var populatedGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            coverageStatus

            if !hasCompletedInitialComputation {
                BrowseLoadingGrid()
            } else if displayedMedia.isEmpty {
                emptyResults
            } else {
                CoverGrid(
                    media: displayedMedia,
                    categories: categories,
                    favoriteContentKeys: favoriteContentKeys,
                    resumableContentKeys: resumableContentKeys
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var emptyResults: some View {
        switch LibraryEmptyCriteria(query: filter, filterState: filterState) {
        case .none:
            ContentUnavailableView {
                Label("No local streams loaded", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Categories sync first. Open a category to load its streams into the local library.")
            }
        case .queryOnly:
            ContentUnavailableView {
                Label("No titles match your search", systemImage: "magnifyingglass")
            } description: {
                Text("Try a different title or clear the search.")
            } actions: {
                Button("Clear Search") {
                    clearSearchAndFilters()
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
                Button("Clear Search and Filters", action: clearSearchAndFilters)
            }
        }
    }

    @ViewBuilder
    private var coverageStatus: some View {
        if selectedCategory == nil, let message = visibleHydrationCoverage.message {
            Label(message, systemImage: "externaldrive.badge.questionmark")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)
        }
    }
}

private struct BrowseLoadingGrid: View {
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay {
                            VStack(alignment: .leading, spacing: 10) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.white.opacity(0.35))
                                    .frame(height: 12)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.white.opacity(0.24))
                                    .frame(width: 72, height: 10)
                            }
                            .padding(12)
                        }
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .redacted(reason: .placeholder)
                        .accessibilityHidden(true)
                }
            }
            .libraryShimmer()
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .accessibilityLabel("Loading streams")
    }
}

private struct CoverGrid: View {
    private enum BrowseLayout {
        static let minimumPosterWidth: CGFloat = 150
        static let posterAspectRatio: CGFloat = 2 / 3
    }
    
    let media: [Media]
    let categories: [Category]
    let favoriteContentKeys: Set<String>
    let resumableContentKeys: Set<String>
    var body: some View {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                    if media.isEmpty {
                        ForEach(0..<10) { idx in
                            BrowseSkeletonTile()
                        }
                    } else {
                        ForEach(media) { media in
                            NavigationLink {
                                MediaDetailDestination(media: media, categoryTitle: categoryTitle(for: media))
                            } label: {
                                BrowsePosterTile(media: media, isFavorite: isFavorite(media), isResumable: isResumable(media))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    
    private var gridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: BrowseLayout.minimumPosterWidth),
                spacing: 16,
                alignment: .top
            )
        ]
    }
    
    private func categoryTitle(for media: Media) -> String? {
        guard let categoryID = media.categoryID else { return nil }
        return categories.first { $0.id == categoryID }?.title
    }

    private func isFavorite(_ media: Media) -> Bool {
        favoriteContentKeys.contains(FavoriteStore.contentKey(mediaType: media.type, sourceID: media.sourceID))
    }

    private func isResumable(_ media: Media) -> Bool {
        resumableContentKeys.contains(FavoriteStore.contentKey(mediaType: media.type, sourceID: media.sourceID))
    }
    
    
    private struct BrowsePosterTile: View {
        let media: Media
        let isFavorite: Bool
        let isResumable: Bool
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .top) {
                    artwork
                    badgeRow
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.12))
                .clipShape(.rect(cornerRadius: 8))
                .aspectRatio(BrowseLayout.posterAspectRatio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))
                
                Text(media.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        
        @ViewBuilder
        private var artwork: some View {
            AsyncImage(url: media.coverURL) { phase in
                if let image = phase.image {
                    image.boundedCoverArtwork()
                } else if phase.error != nil {
                    VStack {
                        Spacer()
                        Text(media.title)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    BrowseSkeletonTile()
                }
            }
        }
        
        private var badgeRow: some View {
            HStack {
                if let ratingText = media.rating?.formatted() {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                        Text(ratingText)
                            .fontWeight(.semibold)
                    }
                    .font(.footnote)
                    .padding(.horizontal, 2)
                    .padding(4)
                    .background(.thinMaterial)
                    .clipShape(.rect(cornerRadius: 8))
                }

                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(6)
                        .background(.thinMaterial)
                        .clipShape(.rect(cornerRadius: 8))
                }

                if isResumable {
                    Image(systemName: "play.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(6)
                        .background(.thinMaterial)
                        .clipShape(.rect(cornerRadius: 8))
                }
               Spacer()
            }
            .padding(6)
        }
    }
    
    private struct BrowseSkeletonGrid: View {
        let columns: [GridItem]
        private let itemCount = 12
        
        var body: some View {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(0..<itemCount, id: \.self) { _ in
                    BrowseSkeletonTile()
                }
            }
        }
    }
    
    private struct BrowseSkeletonTile: View {
        var body: some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .overlay {
                    VStack(alignment: .leading, spacing: 10) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.35))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.24))
                            .frame(width: 72, height: 10)
                    }
                    .padding(12)
                }
                .aspectRatio(2 / 3, contentMode: .fit)
                .modifier(ShimmerEffect())
                .accessibilityHidden(true)
        }
    }
    
    private struct ShimmerEffect: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var phase: CGFloat = -1

        @ViewBuilder
        func body(content: Content) -> some View {
            if reduceMotion {
                content
            } else {
                content
                    .overlay {
                        GeometryReader { proxy in
                            let width = proxy.size.width
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color.white.opacity(0.18),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: max(width * 0.45, 1))
                            .rotationEffect(.degrees(18))
                            .offset(x: phase * width * 1.6)
                        }
                        .allowsHitTesting(false)
                        .clipShape(.rect(cornerRadius: 8))
                    }
                    .onAppear {
                        guard phase < 0 else { return }
                        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                            phase = 1.1
                        }
                    }
            }
        }
    }
}


struct LibraryFilterBar: View {
    let categories: [Category]
    var showsCategoryFilter = true
    var showsGroupFilter = true
    var showsRatingFilter = true
    var showsSort = true
    @Binding var state: LibraryFilterState
    let clearFilters: () -> Void
    @State private var isGroupSelectorPresented = false

    private var groupSections: Array<(key: String, value: [Category])> {
        Dictionary(grouping: categories) { category in
            category.groupKey
        }
        .map { key, value in
            (
                key,
                value.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
            )
        }
        .sorted { lhs, rhs in
            CategoryGrouping.title(for: lhs.key).localizedStandardCompare(CategoryGrouping.title(for: rhs.key)) == .orderedAscending
        }
    }

    private var categorySections: Array<(key: String, value: [Category])> {
        let matchingCategories = LibraryCategoryFilterOptions.categories(
            categories,
            matchingGroupKeys: state.selectedGroupKeys
        )
        return Dictionary(grouping: matchingCategories) { category in
            category.groupKey
        }
        .map { key, value in
            (
                key,
                value.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
            )
        }
        .sorted { lhs, rhs in
            CategoryGrouping.title(for: lhs.key).localizedStandardCompare(CategoryGrouping.title(for: rhs.key)) == .orderedAscending
        }
    }

    private var selectedCategory: Category? {
        categories.first { $0.id == state.selectedCategoryID }
    }

    private var activeFilterCount: Int {
        var count = 0
        if showsCategoryFilter, state.selectedCategoryID != nil { count += 1 }
        if showsGroupFilter, !state.selectedGroupKeys.isEmpty { count += 1 }
        if showsRatingFilter, state.minimumRating != nil { count += 1 }
        return count
    }

    private var hasActiveFilters: Bool { activeFilterCount > 0 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if hasActiveFilters {
                    Button(action: clearFilters) {
                        FilterPill(
                            title: "",
                            systemImage: "line.3.horizontal.decrease",
                            badgeCount: activeFilterCount,
                            isActive: true,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove all \(activeFilterCount) active filters")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                if showsGroupFilter {
                    Button {
                        isGroupSelectorPresented = true
                    } label: {
                        FilterPill(
                            title: "Groups",
                            badgeCount: state.selectedGroupKeys.isEmpty ? 0 : state.selectedGroupKeys.count,
                            isActive: !state.selectedGroupKeys.isEmpty,
                            showsChevron: true
                        )
                    }
                    .accessibilityLabel(
                        state.selectedGroupKeys.isEmpty
                        ? "Group filter inactive"
                        : "Group filter active, \(state.selectedGroupKeys.count) selected"
                    )
                    .buttonStyle(.plain)
                }

                if showsCategoryFilter {
                    Menu {
                        Button {
                            state.selectedCategoryID = nil
                        } label: {
                            Label("All Categories", systemImage: state.selectedCategoryID == nil ? "checkmark" : "rectangle.grid.1x2")
                        }

                        ForEach(categorySections, id: \.key) { section in
                            Section(CategoryGrouping.title(for: section.key)) {
                                ForEach(section.value) { category in
                                    Button {
                                        state.selectedCategoryID = category.id
                                    } label: {
                                        Label(
                                            category.displayTitle,
                                            systemImage: state.selectedCategoryID == category.id ? "checkmark" : "folder"
                                        )
                                    }
                                }
                            }
                        }
                    } label: {
                        FilterPill(
                            title: selectedCategory?.displayTitle ?? "Category",
                            isActive: state.selectedCategoryID != nil,
                            showsChevron: true
                        )
                    }
                    .accessibilityLabel(
                        state.selectedCategoryID == nil
                        ? "Category filter inactive"
                        : "Category filter active, \(selectedCategory?.displayTitle ?? "selected category")"
                    )
                }

                if showsRatingFilter {
                    Menu {
                    Button {
                        state.minimumRating = nil
                    } label: {
                        Label("Any Rating", systemImage: state.minimumRating == nil ? "checkmark" : "star")
                    }

                    ForEach([9.0, 8.0, 7.0], id: \.self) { rating in
                        Button {
                            state.minimumRating = rating
                        } label: {
                            Label(
                                "\(rating.formatted())+",
                                systemImage: state.minimumRating == rating ? "checkmark" : "star.fill"
                            )
                        }
                    }
                    } label: {
                        FilterPill(
                            title: state.minimumRating.map { "\($0.formatted())+ Rating" } ?? "Rating",
                            isActive: state.minimumRating != nil,
                            showsChevron: true
                        )
                    }
                    .accessibilityLabel(
                        state.minimumRating.map { "Rating filter active, minimum \($0.formatted())" } ?? "Rating filter inactive"
                    )
                }

                if showsSort {
                    Menu {
                        ForEach(BrowseSort.allCases) { sort in
                            Button {
                                state.sort = sort
                            } label: {
                                Label(
                                    sort.title,
                                    systemImage: state.sort == sort ? "checkmark" : sort.systemImage
                                )
                            }
                        }
                    } label: {
                        FilterPill(
                            title: state.sort.compactTitle,
                            isActive: state.sort != .title,
                            showsChevron: true
                        )
                    }
                    .accessibilityLabel("Sorted by \(state.sort.title)")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.background)
        .animation(.smooth(duration: 0.25), value: hasActiveFilters)
        .sheet(isPresented: $isGroupSelectorPresented) {
            LibraryGroupFilterSelector(
                groupKeys: groupSections.map(\.key),
                selectedGroupKeys: state.selectedGroupKeys
            ) { selection in
                state.selectedGroupKeys = selection
                if let selectedCategory,
                   !selection.isEmpty,
                   !selection.contains(selectedCategory.groupKey) {
                    state.selectedCategoryID = nil
                }
            }
        }
    }
}

struct LibraryGroupFilterSelector: View {
    let groupKeys: [String]
    let onApply: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var draftSelectedGroupKeys: Set<String>

    init(
        groupKeys: [String],
        selectedGroupKeys: Set<String>,
        onApply: @escaping (Set<String>) -> Void
    ) {
        self.groupKeys = groupKeys
        self.onApply = onApply
        self._draftSelectedGroupKeys = State(initialValue: selectedGroupKeys)
    }

    private var filteredGroupKeys: [String] {
        guard !LibraryQueryNormalizer.isEmpty(searchText) else { return groupKeys }
        return groupKeys.filter {
            LibraryQueryNormalizer.matches(CategoryGrouping.title(for: $0), query: searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        draftSelectedGroupKeys.removeAll()
                    } label: {
                        Label(
                            "All Groups",
                            systemImage: draftSelectedGroupKeys.isEmpty ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }

                Section("Available Groups") {
                    ForEach(filteredGroupKeys, id: \.self) { groupKey in
                        Button {
                            toggle(groupKey)
                        } label: {
                            HStack {
                                Text(CategoryGrouping.title(for: groupKey))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: draftSelectedGroupKeys.contains(groupKey) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(draftSelectedGroupKeys.contains(groupKey) ? Color.accentColor : Color.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Groups")
#if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $searchText, prompt: "Search Groups")
            .compactSearchToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply \(draftSelectedGroupKeys.count)") {
                        onApply(draftSelectedGroupKeys)
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggle(_ groupKey: String) {
        if draftSelectedGroupKeys.contains(groupKey) {
            draftSelectedGroupKeys.remove(groupKey)
        } else {
            draftSelectedGroupKeys.insert(groupKey)
        }
    }
}

extension View {
    @ViewBuilder
    func compactSearchToolbar() -> some View {
#if os(iOS) || os(visionOS)
        searchToolbarBehavior(.minimize)
#else
        self
#endif
    }
}

struct FilterPill: View {
    let title: String
    var systemImage: String? = nil
    var badgeCount = 0
    let isActive: Bool
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }

            if !title.isEmpty {
                Text(title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isActive ? Color.white.opacity(0.22) : Color.secondary.opacity(0.18))
                    .clipShape(Capsule())
            }

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .foregroundStyle(isActive ? Color.white : Color.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor : Color.secondary.opacity(0.14))
        .clipShape(Capsule(style: .continuous))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! appDatabase()
    }
    BrowseScreen(type: .movie)
        .environment(ProviderManager())
}
