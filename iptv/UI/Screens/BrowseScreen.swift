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

    @State private var selectedCategoryID: Category.ID?
    @State private var selectedGroupKeys: Set<String> = []
    @State private var searchText = ""
    @State private var sort: BrowseSort = .title
    @State private var minimumRating: Double?

    @FetchAll
    private var categories: [Category]

    @FetchAll
    private var media: [Media]

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

    private var category: Category? {
        selectedCategoryID.flatMap { categoryProjection.categoryByID[$0] }
    }

    private var hydrationSnapshot: LibraryHydrationSnapshot {
        LibraryHydrationSnapshot(
            categories: categories,
            media: media,
            overrides: session.runtimeHydrationStates
        )
    }

    private var categoryHydrationState: SyncManager.CategoryHydrationState {
        hydrationSnapshot.state(for: category)
    }

    private var visibleHydrationCoverage: LibraryHydrationCoverage {
        hydrationSnapshot.coverage(for: visibleCategories)
    }

    private var fallbackScreenTitle: String {
        if let category {
            return category.title
        }

        return switch type {
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
            selectedCategoryID: selectedCategoryID,
            selectedGroupKeys: selectedGroupKeys,
            minimumRating: minimumRating,
            sort: sort
        )
    }

    init(type: MediaType) {
        self.type = type
        self._categories = FetchAll(Category.where { $0.type.eq(type) })
        self._media = FetchAll(Media.where { $0.type.eq(type) })
    }

    var body: some View {
        VStack(spacing: 0) {
            if visibilitySnapshot != nil, !categories.isEmpty {
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

            content
        }
        .navigationTitle(fallbackScreenTitle)
        .searchable(text: $searchText, prompt: "Search \(fallbackScreenTitle)")
        .task(id: selectedCategoryID) {
            await hydrateSelectedCategoryIfNeeded()
        }
        .task(id: visibilityRequest) {
            prefixVisibilityCache.resolve(visibilityRequest) {
                CategoryPrefixVisibilityStore.snapshot(for: visibilityRequest)
            }
        }
        .onChange(of: categoryProjection.selectableCategoryIDs) { _, categoryIDs in
            var nextState = filterState
            nextState.retainSelections(availableIn: visibleCategories)
            apply(nextState)
        }
    }

    @ViewBuilder
    private var content: some View {
        if visibilitySnapshot == nil {
            ProgressView("Loading category visibility")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if categories.isEmpty {
            ContentUnavailableView {
                Text("No \(fallbackScreenTitle) available")
            } description: {
                Text("The configured provider did not return any \(fallbackScreenTitle.lowercased()).")
            }
        } else if visibleCategories.isEmpty {
            ContentUnavailableView {
                Label("All category groups hidden", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Clear prefix visibility settings to show \(fallbackScreenTitle.lowercased()).")
            } actions: {
                Button("Clear Prefix Visibility") {
                    CategoryPrefixVisibilityStore.setHiddenGroupKeys([], for: session.providerID)
                }
            }
        } else {
            CoverGridSection(
                type: type,
                filterState: filterState,
                filter: searchText,
                categories: categories,
                media: media,
                hiddenGroupKeys: hiddenGroupKeys,
                selectedCategory: category,
                hydrationState: categoryHydrationState,
                visibleHydrationCoverage: visibleHydrationCoverage,
                clearFilters: clearFilters,
                clearSearchAndFilters: clearSearchAndFilters,
                retryHydration: {
                    Task { await hydrateSelectedCategory(force: true) }
                }
            )
        }
    }

    private func clearFilters() {
        var nextState = filterState
        nextState.clearFilters()
        apply(nextState)
    }

    private func clearSearchAndFilters() {
        clearFilters()
        searchText = ""
    }

    private func apply(_ state: LibraryFilterState) {
        selectedCategoryID = state.selectedCategoryID
        selectedGroupKeys = state.selectedGroupKeys
        minimumRating = state.minimumRating
        sort = state.sort
    }

    private func hydrateSelectedCategoryIfNeeded() async {
        guard categoryHydrationState == .unhydrated else { return }
        await hydrateSelectedCategory(force: false)
    }

    private func hydrateSelectedCategory(force: Bool) async {
        guard let category else { return }
        if !force, session.hydrationState(for: category) != .unhydrated { return }

        do {
            try await session.update(type, in: category.id)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }
}

struct CoverGridSection: View {
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

    private var filteredMedia: [Media] {
        LibraryFilterEngine.filteredMedia(
            media,
            categories: categories,
            state: filterState,
            hiddenGroupKeys: hiddenGroupKeys,
            query: filter
        )
    }

    private var favoriteContentKeys: Set<String> {
        Set(
            favorites
                .filter { $0.providerID == session.providerID }
                .map { FavoriteStore.contentKey(mediaType: $0.mediaType, sourceID: $0.sourceID) }
        )
    }

    private var resumableContentKeys: Set<String> {
        Set(
            watchActivities
                .filter { $0.providerID == session.providerID && $0.isResumeEligible }
                .map { FavoriteStore.contentKey(mediaType: $0.mediaType, sourceID: $0.sourceID) }
        )
    }

    @ViewBuilder
    var body: some View {
        if let selectedCategory {
            switch hydrationState {
            case .unhydrated:
                ContentUnavailableView {
                    Label("Loading \(selectedCategory.title)", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("This category is being hydrated from the provider into the local database.")
                }
            case .loading:
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

    @ViewBuilder
    private var populatedGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            coverageStatus

            if filteredMedia.isEmpty {
                emptyResults
            } else {
                CoverGrid(
                    media: filteredMedia,
                    categories: categories,
                    favoriteContentKeys: favoriteContentKeys,
                    resumableContentKeys: resumableContentKeys
                )
                .id(filterState)
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
        GridItem(.adaptive(minimum: 150, maximum: 170), spacing: 16, alignment: .top)
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
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .accessibilityLabel("Loading streams")
    }
}

private struct CoverGrid: View {
    private enum BrowseLayout {
        static let standardPosterWidth: CGFloat = 170
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
                .adaptive(
                    minimum: BrowseLayout.minimumPosterWidth,
                    maximum: BrowseLayout.standardPosterWidth
                ),
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
    @Binding var state: LibraryFilterState
    let clearFilters: () -> Void

    private var groupSections: Array<(key: String, value: [Category])> {
        Dictionary(grouping: categories) { category in
            CategoryGrouping.key(for: category.title)
        }
        .map { key, value in
            (
                key,
                value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            )
        }
        .sorted { lhs, rhs in
            CategoryGrouping.title(for: lhs.key).localizedStandardCompare(CategoryGrouping.title(for: rhs.key)) == .orderedAscending
        }
    }

    private var selectedCategory: Category? {
        categories.first { $0.id == state.selectedCategoryID }
    }

    private var activeGroupTitles: String {
        state.selectedGroupKeys
            .sorted { CategoryGrouping.title(for: $0) < CategoryGrouping.title(for: $1) }
            .map { CategoryGrouping.title(for: $0) }
            .joined(separator: ", ")
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Text("\(state.activeFilterCount) filter\(state.activeFilterCount == 1 ? "" : "s") applied")

                    if state.hasActiveFilters {
                        Button(role: .destructive, action: clearFilters) {
                            Label("Clear All Filters", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    FilterPill(
                        title: "Filters",
                        systemImage: "line.3.horizontal.decrease.circle",
                        badgeCount: state.activeFilterCount,
                        isActive: state.hasActiveFilters,
                        showsChevron: true
                    )
                }
                .accessibilityLabel(state.hasActiveFilters ? "\(state.activeFilterCount) filters active" : "No filters active")

                Menu {
                    Button {
                        state.selectedCategoryID = nil
                    } label: {
                        Label("All Categories", systemImage: state.selectedCategoryID == nil ? "checkmark" : "rectangle.grid.1x2")
                    }

                    ForEach(groupSections, id: \.key) { section in
                        Section(CategoryGrouping.title(for: section.key)) {
                            ForEach(section.value) { category in
                                Button {
                                    state.selectedCategoryID = category.id
                                } label: {
                                    Label(
                                        category.title,
                                        systemImage: state.selectedCategoryID == category.id ? "checkmark" : "folder"
                                    )
                                }
                            }
                        }
                    }
                } label: {
                    FilterPill(
                        title: selectedCategory?.title ?? "Category",
                        systemImage: "folder",
                        isActive: state.selectedCategoryID != nil,
                        showsChevron: true
                    )
                }
                .accessibilityLabel(
                    state.selectedCategoryID == nil
                    ? "Category filter inactive"
                    : "Category filter active, \(selectedCategory?.title ?? "selected category")"
                )

                Menu {
                    Button {
                        state.selectedGroupKeys.removeAll()
                    } label: {
                        Label("All Groups", systemImage: state.selectedGroupKeys.isEmpty ? "checkmark" : "line.3.horizontal")
                    }

                    ForEach(groupSections, id: \.key) { section in
                        Button {
                            if state.selectedGroupKeys.contains(section.key) {
                                state.selectedGroupKeys.remove(section.key)
                            } else {
                                state.selectedGroupKeys.insert(section.key)
                            }
                        } label: {
                            Label(
                                CategoryGrouping.title(for: section.key),
                                systemImage: state.selectedGroupKeys.contains(section.key) ? "checkmark" : "line.3.horizontal"
                            )
                        }
                    }
                } label: {
                    FilterPill(
                        title: state.selectedGroupKeys.isEmpty ? "Group" : activeGroupTitles,
                        systemImage: "rectangle.3.group",
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
                        systemImage: "star.fill",
                        isActive: state.minimumRating != nil,
                        showsChevron: true
                    )
                }
                .accessibilityLabel(
                    state.minimumRating.map { "Rating filter active, minimum \($0.formatted())" } ?? "Rating filter inactive"
                )

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
                        systemImage: state.sort.systemImage,
                        isActive: state.sort != .title,
                        showsChevron: true
                    )
                }
                .accessibilityLabel("Sorted by \(state.sort.title)")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.background)
    }
}

struct FilterPill: View {
    let title: String
    let systemImage: String
    var badgeCount = 0
    let isActive: Bool
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)

            Text(title)
                .fontWeight(.semibold)
                .lineLimit(1)

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
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(isActive ? Color.accentColor : Color.secondary.opacity(0.14))
        .clipShape(Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! appDatabase()
    }
    BrowseScreen(type: .movie)
        .environment(ProviderManager())
}
