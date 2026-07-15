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
    @AppStorage(CategoryPrefixVisibilityStore.revisionKey) private var prefixVisibilityRevision = 0
    @State private var prefixVisibilityCache = CategoryPrefixVisibilityCache()
    @State private var selectedGroupKeys: Set<String> = []
    @State private var categorySearchText = ""
    @FetchAll private var categories: [Category]
    @Fetch private var mediaCounts = LibraryMediaCountsRequest.Value()

    init() {
        self._categories = FetchAll(Category.where { $0.type.eq(MediaType.live) })
        self._mediaCounts = Fetch(
            wrappedValue: LibraryMediaCountsRequest.Value(),
            LibraryMediaCountsRequest(type: .live)
        )
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if visibilitySnapshot != nil, !categories.isEmpty {
                    LiveFilterBar(
                        categories: visibleCategories,
                        selectedGroupKeys: $selectedGroupKeys,
                        clearFilters: { selectedGroupKeys.removeAll() }
                    )
                    Divider()
                }

                content
            }
            .navigationTitle("Live")
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
        } else if landingCategories.isEmpty {
            ContentUnavailableView.search(text: categorySearchText)
        } else {
            LibraryCategoryList(
                categories: landingCategories,
                hydrationSnapshot: hydrationSnapshot,
                contentName: "channel"
            ) { category in
                LiveCategoryScreen(category: category)
            }
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

}

private struct LiveCategoryScreen: View {
    let category: Category

    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @State private var searchText = ""
    @State private var sort: BrowseSort = .title
    @State private var selectedGuideChannel: Media?
    @State private var displayedChannels: [Media] = []
    @State private var hasCompletedInitialComputation = false
    @State private var catalogRevision = 0
    @FetchAll private var channels: [Media]
    @Fetch private var mediaCounts = LibraryMediaCountsRequest.Value()

    init(category: Category) {
        self.category = category
        self._channels = FetchAll()
        self._mediaCounts = Fetch(
            wrappedValue: LibraryMediaCountsRequest.Value(),
            LibraryMediaCountsRequest(type: .live)
        )
    }

    private var hydrationState: SyncManager.CategoryHydrationState {
        LibraryHydrationSnapshot(
            categories: [category],
            mediaCountsByCategoryID: mediaCounts.byCategoryID,
            overrides: session.runtimeHydrationStates
        ).state(for: category)
    }

    private var filterState: LibraryFilterState {
        LibraryFilterState(sort: sort)
    }

    private var filterRequest: LibraryFilterRequest {
        LibraryFilterRequest(
            media: channels,
            categories: [category],
            state: filterState,
            hiddenGroupKeys: [],
            query: searchText,
            includedTypes: [.live]
        )
    }

    private var filterTaskID: LibraryFilterTaskID {
        LibraryFilterTaskID(
            state: filterState,
            hiddenGroupKeys: [],
            query: searchText,
            includedTypes: [.live],
            catalogRevision: catalogRevision
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            LiveMediaFilterBar(sort: $sort)
            Divider()
            content
        }
        .navigationTitle(category.displayTitle)
        .searchable(text: $searchText, prompt: "Search \(category.displayTitle)")
        .compactSearchToolbar()
        .task(id: category.id) {
            await hydrate(force: false)
        }
        .task(id: category.id) {
            do {
                try await $channels.load(
                    Media.where { $0.type.eq(MediaType.live).and($0.categoryID.eq(category.id)) }
                )
            } catch {
                return
            }
        }
        .task(id: filterTaskID) {
            if !filterTaskID.normalizedQuery.isEmpty {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
            }
            let result = await LibraryFilterEngine.filteredMedia(inBackground: filterRequest)
            guard !Task.isCancelled else { return }
            displayedChannels = result
            hasCompletedInitialComputation = true
        }
        .task(id: channels.count) {
            catalogRevision &+= 1
        }
        .sheet(item: $selectedGuideChannel) { channel in
            LiveGuideSheet(channel: channel)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch hydrationState {
        case .unhydrated, .loading:
            LiveLoadingList()
        case .empty:
            ContentUnavailableView {
                Label("No channels in \(category.displayTitle)", systemImage: "tray")
            } description: {
                Text("The provider returned this live category, but no channels were found for it.")
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn’t load \(category.displayTitle)", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    Task { await hydrate(force: true) }
                }
            }
        case .populated:
            channelList(
                title: category.displayTitle,
                emptyTitle: "No channels match",
                emptyMessage: "Clear search or filters to show the local channels in this category."
            )
        }
    }

    private func channelList(title: String, emptyTitle: String, emptyMessage: String) -> some View {
        Group {
            if !hasCompletedInitialComputation {
                ProgressView("Filtering local live channels")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedChannels.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "magnifyingglass")
                } description: {
                    Text(emptyMessage)
                } actions: {
                    if sort != .title || !LibraryQueryNormalizer.isEmpty(searchText) {
                        Button("Clear Search and Sort", action: clearSearchAndSort)
                    }
                }
            } else {
                List {
                    Section {
                        ForEach(displayedChannels) { channel in
                            HStack(spacing: 8) {
                                Button {
                                    player.loadLiveChannel(channel, channels: displayedChannels)
                                } label: {
                                    LiveChannelRow(channel: channel, categoryTitle: categoryTitle(for: channel))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Play \(channel.title)")

                                Button {
                                    selectedGuideChannel = channel
                                } label: {
                                    Image(systemName: "list.bullet.rectangle")
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Guide for \(channel.title)")
                            }
                        }
                    } header: {
                        Text(title)
                    } footer: {
                        Text("Search, grouping, sorting, and previous/next channel zapping use this local list. EPG, catch-up, and DVR require guide data not supplied by the current service layer.")
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #endif
            }
        }
    }

    private func clearSearchAndSort() {
        sort = .title
        searchText = ""
    }

    private func hydrate(force: Bool) async {
        if !force, hydrationState != .unhydrated { return }

        do {
            try await session.update(.live, in: category.id)
        } catch {
            return
        }
    }

    private func categoryTitle(for channel: Media) -> String? {
        channel.categoryID == category.id ? category.title : nil
    }
}

private struct LiveGuideSheet: View {
    let channel: Media

    @Environment(ProviderManager.self) private var providerManager
    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var programmes: [LiveGuideProgramme] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading guide")
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Guide Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else if programmes.isEmpty {
                    ContentUnavailableView {
                        Label("No Guide Data", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("The provider returned no current or upcoming programmes for this channel.")
                    }
                } else {
                    List(programmes) { programme in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(programme.title)
                                .font(.headline)
                            Text("\(programme.start.formatted(date: .omitted, time: .shortened))–\(programme.end.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let description = programme.description {
                                Text(description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if channel.supportsCatchup && programme.archiveAvailable && programme.start < .now {
                                Button("Play from Start", systemImage: "gobackward") {
                                    playCatchup(programme)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(channel.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            guard let provider = try providerManager.activeProviderConfiguration() else {
                throw LiveGuideService.GuideError.invalidEndpoint
            }
            programmes = try await LiveGuideService().programmes(for: channel, provider: provider)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func playCatchup(_ programme: LiveGuideProgramme) {
        do {
            guard let provider = try providerManager.activeProviderConfiguration() else {
                throw LiveGuideService.GuideError.invalidEndpoint
            }
            let url = try LiveGuideService().catchupURL(
                for: programme,
                channel: channel,
                provider: provider
            )
            dismiss()
            player.load(channel, presentation: .fullWindow, sourceURL: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LiveFilterBar: View {
    let categories: [Category]
    @Binding var selectedGroupKeys: Set<String>
    let clearFilters: () -> Void
    @State private var isGroupSelectorPresented = false

    private var groupSections: Array<(key: String, value: [Category])> {
        Dictionary(grouping: categories) { category in
            category.groupKey
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

    private var activeFilterCount: Int { selectedGroupKeys.isEmpty ? 0 : 1 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if activeFilterCount > 0 {
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

                Button {
                    isGroupSelectorPresented = true
                } label: {
                    FilterPill(
                        title: "Groups",
                        badgeCount: selectedGroupKeys.isEmpty ? 0 : selectedGroupKeys.count,
                        isActive: !selectedGroupKeys.isEmpty,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.background)
        .animation(.smooth(duration: 0.25), value: activeFilterCount)
        .sheet(isPresented: $isGroupSelectorPresented) {
            LibraryGroupFilterSelector(
                groupKeys: groupSections.map(\.key),
                selectedGroupKeys: selectedGroupKeys
            ) { selectedGroupKeys = $0 }
        }
    }
}

private struct LiveMediaFilterBar: View {
    @Binding var sort: BrowseSort

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
                        isActive: sort != .title,
                        showsChevron: true
                    )
                }
                .accessibilityLabel("Sorted by \(sort.title)")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.background)
    }
}

private struct LiveLoadingList: View {
    var body: some View {
        List {
            Section {
                ForEach(0..<12, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 7) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.secondary.opacity(0.16))
                                .frame(height: 13)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.secondary.opacity(0.11))
                                .frame(width: 120, height: 10)
                        }
                    }
                    .padding(.vertical, 4)
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
                }
            }
        }
        .libraryShimmer()
        #if os(macOS)
        .listStyle(.inset)
        #endif
        .accessibilityLabel("Loading channels")
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
