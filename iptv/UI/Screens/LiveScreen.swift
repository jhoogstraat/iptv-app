//
//  LiveScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import SwiftUI
import SQLiteData

struct LiveScreen: View {
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @AppStorage(CategoryPrefixVisibilityStore.revisionKey) private var prefixVisibilityRevision = 0
    @State private var prefixVisibilityCache = CategoryPrefixVisibilityCache()

    @FetchAll
    private var categories: [Category]

    @FetchAll
    private var channels: [Media]

    @State private var selectedCategoryID: Category.ID?
    @State private var selectedGroupKeys: Set<String> = []
    @State private var searchText = ""
    @State private var sort: BrowseSort = .title

    init() {
        self._categories = FetchAll(Category.where { $0.type.eq(MediaType.live) })
        self._channels = FetchAll(Media.where { $0.type.eq(MediaType.live) })
    }

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

    private var selectedCategory: Category? {
        selectedCategoryID.flatMap { categoryProjection.categoryByID[$0] }
    }

    private var hydrationSnapshot: LibraryHydrationSnapshot {
        LibraryHydrationSnapshot(
            categories: categories,
            media: channels,
            overrides: session.runtimeHydrationStates
        )
    }

    private var selectedHydrationState: SyncManager.CategoryHydrationState {
        hydrationSnapshot.state(for: selectedCategory)
    }

    private var filterState: LibraryFilterState {
        LibraryFilterState(
            selectedCategoryID: selectedCategoryID,
            selectedGroupKeys: selectedGroupKeys,
            sort: sort
        )
    }

    private var filteredChannels: [Media] {
        LibraryFilterEngine.filteredMedia(
            channels,
            categories: categories,
            state: filterState,
            hiddenGroupKeys: hiddenGroupKeys,
            query: searchText
        )
    }

    private var hasLocalSearchOrGroupFilter: Bool {
        !LibraryQueryNormalizer.isEmpty(searchText) || !selectedGroupKeys.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if visibilitySnapshot != nil, !categories.isEmpty {
                    LiveFilterBar(
                        categories: visibleCategories,
                        selectedCategoryID: $selectedCategoryID,
                        selectedGroupKeys: $selectedGroupKeys,
                        sort: $sort,
                        clearFilters: clearFilters
                    )
                    Divider()
                }

                content
            }
            .navigationTitle(selectedCategory?.title ?? "Live")
            .searchable(text: $searchText, prompt: "Search local live channels")
            .task(id: selectedCategoryID) {
                await hydrateSelectedCategoryIfNeeded()
            }
            .task(id: visibilityRequest) {
                prefixVisibilityCache.resolve(visibilityRequest) {
                    CategoryPrefixVisibilityStore.snapshot(for: visibilityRequest)
                }
            }
            .onChange(of: categoryProjection.selectableCategoryIDs) { _, _ in
                if let selectedCategoryID,
                   !categoryProjection.selectableCategoryIDs.contains(selectedCategoryID) {
                    self.selectedCategoryID = nil
                }

                selectedGroupKeys.formIntersection(categoryProjection.selectableGroupKeys)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if visibilitySnapshot == nil {
            ProgressView("Loading category visibility")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if categories.isEmpty {
            liveCategoryEmptyState
        } else if visibleCategories.isEmpty {
            ContentUnavailableView {
                Label("All live category groups hidden", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Clear prefix visibility settings to show live categories and channels.")
            } actions: {
                Button("Clear Prefix Visibility") {
                    CategoryPrefixVisibilityStore.setHiddenGroupKeys([], for: session.providerID)
                }
            }
        } else if selectedCategory == nil, !hasLocalSearchOrGroupFilter, channels.isEmpty {
            liveCategoryPicker
        } else if let selectedCategory {
            selectedCategoryContent(selectedCategory)
        } else {
            channelList(
                title: "Local live channels",
                emptyTitle: "No local live channels match",
                emptyMessage: "Open a category to hydrate channels first. Search and filters only use live rows already stored locally."
            )
        }
    }

    @ViewBuilder
    private var liveCategoryEmptyState: some View {
        switch session.liveSyncStatus {
        case .active:
            VStack(spacing: 12) {
                ProgressView()
                Text("Syncing live categories")
                    .font(.headline)
                Text("Live channels will appear after the provider category sync completes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure:
            ContentUnavailableView {
                Label("Couldn’t sync live categories", systemImage: "exclamationmark.triangle")
            } description: {
                Text(session.syncErrorMessage ?? "Retry provider sync from Settings.")
            }
        case .idle, .success:
            ContentUnavailableView {
                Label("No live categories", systemImage: "dot.radiowaves.left.and.right")
            } description: {
                Text("The configured provider did not return live channel categories during local sync.")
            }
        }
    }

    private var liveCategoryPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                unavailableGuideCallout

                Text("Choose a category to load its channels")
                    .font(.headline)
                    .padding(.horizontal)

                LazyVStack(spacing: 10) {
                    ForEach(visibleCategories) { category in
                        Button {
                            selectedCategoryID = category.id
                        } label: {
                            LiveCategoryRow(
                                category: category,
                                hydrationState: hydrationSnapshot.state(for: category)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func selectedCategoryContent(_ category: Category) -> some View {
        switch selectedHydrationState {
        case .unhydrated:
            ContentUnavailableView {
                Label("Loading \(category.title)", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("This live category is being hydrated from the provider into the local database.")
            }
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading \(category.title)")
                    .font(.headline)
                Text("Channel rows are being saved locally before display.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView {
                Label("No channels in \(category.title)", systemImage: "tray")
            } description: {
                Text("The provider returned this live category, but no channels were found for it.")
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn’t load \(category.title)", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    Task { await hydrateSelectedCategory(force: true) }
                }
            }
        case .populated:
            channelList(
                title: category.title,
                emptyTitle: "No channels match",
                emptyMessage: "Clear search or filters to show the local channels in this category."
            )
        }
    }

    private func channelList(title: String, emptyTitle: String, emptyMessage: String) -> some View {
        Group {
            if filteredChannels.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "magnifyingglass")
                } description: {
                    Text(emptyMessage)
                } actions: {
                    if filterState.hasActiveFilters || !LibraryQueryNormalizer.isEmpty(searchText) {
                        Button("Clear Search and Filters", action: clearFiltersAndSearch)
                    }
                }
            } else {
                List {
                    Section {
#if os(tvOS)
                        unavailableGuideCallout
#else
                        unavailableGuideCallout
                            .listRowSeparator(.hidden)
#endif
                    }

                    Section {
                        ForEach(filteredChannels) { channel in
                            Button {
                                player.load(channel, presentation: .fullWindow)
                            } label: {
                                LiveChannelRow(channel: channel, categoryTitle: categoryTitle(for: channel))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play \(channel.title)")
                        }
                    } header: {
                        Text(title)
                    } footer: {
                        Text("Search, grouping, and sorting are local. EPG, catch-up, zapping, DVR, and guide rows are not available yet.")
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #endif
            }
        }
    }

    private var unavailableGuideCallout: some View {
        Label {
            Text("Live playback is available. EPG, catch-up, channel zapping, DVR, and guide rows are not implemented yet.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func clearFilters() {
        selectedCategoryID = nil
        selectedGroupKeys.removeAll()
        sort = .title
    }

    private func clearFiltersAndSearch() {
        clearFilters()
        searchText = ""
    }

    private func hydrateSelectedCategoryIfNeeded() async {
        guard selectedHydrationState == .unhydrated else { return }
        await hydrateSelectedCategory(force: false)
    }

    private func hydrateSelectedCategory(force: Bool) async {
        guard let selectedCategory else { return }
        if !force, session.hydrationState(for: selectedCategory) != .unhydrated { return }

        do {
            try await session.update(.live, in: selectedCategory.id)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func categoryTitle(for channel: Media) -> String? {
        guard let categoryID = channel.categoryID else { return nil }
        return categoryProjection.categoryByID[categoryID]?.title
    }
}

private struct LiveFilterBar: View {
    let categories: [Category]
    @Binding var selectedCategoryID: Category.ID?
    @Binding var selectedGroupKeys: Set<String>
    @Binding var sort: BrowseSort
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
        categories.first { $0.id == selectedCategoryID }
    }

    private var activeFilterCount: Int {
        var count = 0
        if selectedCategoryID != nil { count += 1 }
        if !selectedGroupKeys.isEmpty { count += 1 }
        if sort != .title { count += 1 }
        return count
    }

    private var activeGroupTitles: String {
        selectedGroupKeys
            .sorted { CategoryGrouping.title(for: $0) < CategoryGrouping.title(for: $1) }
            .map { CategoryGrouping.title(for: $0) }
            .joined(separator: ", ")
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Text("\(activeFilterCount) filter\(activeFilterCount == 1 ? "" : "s") applied")

                    if activeFilterCount > 0 {
                        Button(role: .destructive, action: clearFilters) {
                            Label("Clear All Filters", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    FilterPill(
                        title: "Filters",
                        systemImage: "line.3.horizontal.decrease.circle",
                        badgeCount: activeFilterCount,
                        isActive: activeFilterCount > 0,
                        showsChevron: true
                    )
                }

                Menu {
                    Button {
                        selectedCategoryID = nil
                    } label: {
                        Label("All Hydrated Categories", systemImage: selectedCategoryID == nil ? "checkmark" : "rectangle.grid.1x2")
                    }

                    ForEach(groupSections, id: \.key) { section in
                        Section(CategoryGrouping.title(for: section.key)) {
                            ForEach(section.value) { category in
                                Button {
                                    selectedCategoryID = category.id
                                } label: {
                                    Label(
                                        category.title,
                                        systemImage: selectedCategoryID == category.id ? "checkmark" : "folder"
                                    )
                                }
                            }
                        }
                    }
                } label: {
                    FilterPill(
                        title: selectedCategory?.title ?? "Category",
                        systemImage: "folder",
                        isActive: selectedCategoryID != nil,
                        showsChevron: true
                    )
                }

                Menu {
                    Button {
                        selectedGroupKeys.removeAll()
                    } label: {
                        Label("All Groups", systemImage: selectedGroupKeys.isEmpty ? "checkmark" : "line.3.horizontal")
                    }

                    ForEach(groupSections, id: \.key) { section in
                        Button {
                            if selectedGroupKeys.contains(section.key) {
                                selectedGroupKeys.remove(section.key)
                            } else {
                                selectedGroupKeys.insert(section.key)
                            }
                        } label: {
                            Label(
                                CategoryGrouping.title(for: section.key),
                                systemImage: selectedGroupKeys.contains(section.key) ? "checkmark" : "line.3.horizontal"
                            )
                        }
                    }
                } label: {
                    FilterPill(
                        title: selectedGroupKeys.isEmpty ? "Group" : activeGroupTitles,
                        systemImage: "rectangle.3.group",
                        badgeCount: selectedGroupKeys.isEmpty ? 0 : selectedGroupKeys.count,
                        isActive: !selectedGroupKeys.isEmpty,
                        showsChevron: true
                    )
                }

                Menu {
                    ForEach([BrowseSort.title, .newest], id: \.self) { option in
                        Button {
                            sort = option
                        } label: {
                            Label(option.title, systemImage: sort == option ? "checkmark" : option.systemImage)
                        }
                    }
                } label: {
                    FilterPill(
                        title: sort.compactTitle,
                        systemImage: sort.systemImage,
                        isActive: sort != .title,
                        showsChevron: true
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.background)
    }
}

private struct LiveCategoryRow: View {
    let category: Category
    let hydrationState: SyncManager.CategoryHydrationState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group.bubble")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(.rect(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.10))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    private var statusText: String {
        switch hydrationState {
        case .unhydrated:
            "Not loaded yet"
        case .loading:
            "Loading channels"
        case .empty:
            "Loaded, no channels"
        case let .populated(count):
            "\(count) local channel\(count == 1 ? "" : "s")"
        case .failed:
            "Failed to load"
        }
    }
}

private struct LiveChannelRow: View {
    let channel: Media
    let categoryTitle: String?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: channel.coverURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Image(systemName: "play.tv")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 54, height: 40)
            .background(Color.secondary.opacity(0.12))
            .clipShape(.rect(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(categoryTitle ?? "Live channel")

                    if let streamType = channel.genre, !streamType.isEmpty {
                        Text("•")
                        Text(streamType)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Image(systemName: "play.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
