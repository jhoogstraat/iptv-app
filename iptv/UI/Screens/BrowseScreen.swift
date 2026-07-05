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

    @State private var selectedCategoryID: Category.ID?
    @State private var selectedGroupKeys: Set<String> = []
    @State private var searchText = ""
    @State private var sort: BrowseSort = .title
    @State private var minimumRating: Double?

    @FetchAll
    private var categories: [Category]

    private var category: Category? { categories.first { $0.id == selectedCategoryID } }

    private var hiddenGroupKeys: Set<String> {
        _ = prefixVisibilityRevision
        return CategoryPrefixVisibilityStore.hiddenGroupKeys(for: session.providerID)
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
        self._categories = FetchAll((Category.where { $0.type.eq(type) }))
    }

    var body: some View {
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

            content
        }
        .navigationTitle(fallbackScreenTitle)
        .searchable(text: $searchText, prompt: "Search \(fallbackScreenTitle)")
        .task(id: selectedCategoryID) {
            guard let category, category.updatedAt == nil else {
                return
            }

            do {
                try await session.update(type, in: category.id)
            } catch is CancellationError {
                print("Cancelled update movies task")
            } catch {
                assertionFailure("Failed to update movies: \(error.localizedDescription)")
            }
        }
        .onChange(of: visibleCategoryIDs) { _, ids in
            if let selectedCategoryID, !ids.contains(selectedCategoryID) {
                self.selectedCategoryID = nil
            }

            selectedGroupKeys = selectedGroupKeys.intersection(visibleGroupKeys)
        }
    }

    @ViewBuilder
    private var content: some View {
        if categories.isEmpty {
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
                categories: visibleCategories,
                hiddenGroupKeys: hiddenGroupKeys
            )
        }
    }

    private func clearFilters() {
        selectedCategoryID = nil
        selectedGroupKeys.removeAll()
        minimumRating = nil
    }
}

struct CoverGridSection: View {
    let type: MediaType
    let filterState: LibraryFilterState
    let filter: String
    let categories: [Category]
    let hiddenGroupKeys: Set<String>

    @FetchAll private var media: [Media]

    init(
        type: MediaType,
        filterState: LibraryFilterState,
        filter: String,
        categories: [Category],
        hiddenGroupKeys: Set<String>
    ) {
        self.type = type
        self.filterState = filterState
        self.filter = filter
        self.categories = categories
        self.hiddenGroupKeys = hiddenGroupKeys

        _media = FetchAll(Media.where {
            $0.type.eq(type)
                .and($0.title.contains(filter))
        })
    }

    private var filteredMedia: [Media] {
        LibraryFilterEngine.filteredMedia(
            media,
            categories: categories,
            state: filterState,
            hiddenGroupKeys: hiddenGroupKeys
        )
    }

    var body: some View {
        CoverGrid(media: filteredMedia)
            .id(filterState)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

private struct CoverGrid: View {
    private enum BrowseLayout {
        static let standardPosterWidth: CGFloat = 170
        static let minimumPosterWidth: CGFloat = 150
        static let posterAspectRatio: CGFloat = 2 / 3
    }
    
    let media: [Media]
    
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
                                ContentUnavailableView("Not yet implemented", systemImage: "film")
    //                            MovieDetailScreen(movie: movie)
                            } label: {
                                BrowsePosterTile(media: media)
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
    
    //    private func destination(for media: Media) -> some View {
    //        let video = row
    //        switch contentType {
    //        case .vod:
    //            return AnyView(MovieDetailScreen(video: video))
    //        case .series:
    //            return AnyView(
    //                EpisodeDetailTile(video: video)
    //                    .navigationTitle(video.name)
    //            )
    //        case .live:
    //            return AnyView(
    //                ScopedPlaceholderView(
    //                    title: "Live Episodes Are Unavailable",
    //                    message: "Episode detail only applies to series content."
    //                )
    //                .navigationTitle(video.name)
    //            )
    //        }
    //    }
    
    private struct BrowsePosterTile: View {
        let media: Media
        
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
        @State private var phase: CGFloat = -1
        
        func body(content: Content) -> some View {
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
        .frame(minHeight: 34)
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
