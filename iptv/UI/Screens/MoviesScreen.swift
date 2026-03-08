//
//  MoviesScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import OSLog

enum LoadState {
    case idle
    case fetching
    case error(Error)
    case done
}

struct MoviesScreen: View {
    let contentType: XtreamContentType

    @Environment(Catalog.self) private var catalog
    @Environment(ProviderStore.self) private var providerStore

    @State private var state: LoadState = .idle
    @State private var isPresentingSettings = false
    @State private var queryText = ""
    @State private var selectedCategoryID: String?
    @State private var browseSort: BrowseSort = .title
    @State private var browseResults: [SearchResultItem] = []
    @State private var browseTask: Task<Void, Never>?
    @State private var coverageTask: Task<Void, Never>?
    @State private var searchProgress = SearchIndexProgress(indexedCategories: 0, totalCategories: 0, scope: .all)

    init(contentType: XtreamContentType = .vod) {
        self.contentType = contentType
    }

    var body: some View {
        NavigationStack {
            Group {
                if !providerStore.hasConfiguration {
                    missingProviderView
                } else {
                    contentForState
                }
            }
            .navigationTitle(screenTitle)
            .searchable(text: $queryText, prompt: "Search \(screenTitle)")
            .onChange(of: queryText) { _, _ in
                scheduleBrowseRefresh()
            }
            .onChange(of: selectedCategoryID) { _, _ in
                scheduleBrowseRefresh(debounced: false)
            }
            .onChange(of: browseSort) { _, _ in
                scheduleBrowseRefresh(debounced: false)
            }
            .toolbar {
                if providerStore.hasConfiguration, !categories.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        categoryMenu
                    }

                    ToolbarItem(placement: .primaryAction) {
                        sortMenu
                    }
                }
            }
            .sheet(isPresented: $isPresentingSettings) {
                NavigationStack {
                    SettingsScreen()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    isPresentingSettings = false
                                }
                            }
                        }
                }
                .environment(providerStore)
            }
        }
        .task(id: providerStore.revision) {
            guard providerStore.hasConfiguration else {
                state = .idle
                catalog.reset()
                coverageTask?.cancel()
                browseTask?.cancel()
                browseResults = []
                selectedCategoryID = nil
                return
            }

            await loadCategories(force: true)
        }
        .onDisappear {
            coverageTask?.cancel()
            browseTask?.cancel()
        }
    }

    @ViewBuilder
    private var contentForState: some View {
        switch state {
            case .idle, .fetching:
                ProgressView()

            case .error(let error):
                VStack(spacing: 12) {
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadCategories(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

            case .done:
                if categories.isEmpty {
                    VStack(spacing: 12) {
                        Text(emptyCatalogMessage)
                        Button("Refresh") {
                            Task { await loadCategories(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if searchProgress.totalCategories > 0, !searchProgress.isComplete {
                            Text("Indexing \(searchProgress.indexedCategories)/\(searchProgress.totalCategories) categories")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }

                        if browseResults.isEmpty {
                            if isIndexing {
                                ProgressView("Loading titles...")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ContentUnavailableView(
                                    "No Results",
                                    systemImage: "film",
                                    description: Text(emptyBrowseMessage)
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            ScrollView {
                                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                                    ForEach(browseResults) { item in
                                        NavigationLink {
                                            destination(for: item.video)
                                        } label: {
                                            browseTile(for: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 20)
                            }
                        }
                    }
                }
        }
    }

    private var categoryMenu: some View {
        Menu {
            Section("Category") {
                Text(selectedCategoryName)
            }

            Picker("Category", selection: $selectedCategoryID) {
                Text("All Categories")
                    .tag(Optional<String>.none)
                ForEach(categories) { category in
                    Text(category.name)
                        .tag(Optional(category.id))
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .help(selectedCategoryName)
    }

    private var sortMenu: some View {
        Menu {
            Section("Sort") {
                Text(browseSort.displayName)
            }

            Picker("Sort", selection: $browseSort) {
                ForEach(BrowseSort.allCases, id: \.self) { sort in
                    Text(sort.displayName)
                        .tag(sort)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .help("Sort: \(browseSort.displayName)")
    }

    @ViewBuilder
    private func destination(for video: Video) -> some View {
        switch contentType {
        case .vod:
            MovieDetailScreen(video: video)
        case .series:
            EpisodeDetailTile(video: video)
                .navigationTitle(video.name)
        case .live:
            ScopedPlaceholderView(
                title: "Live Episodes Are Unavailable",
                message: "Episode detail only applies to series content."
            )
                .navigationTitle(video.name)
        }
    }

    private var missingProviderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal.fill")
                .font(.largeTitle)
            Text("Configure Provider")
                .font(.title3.weight(.semibold))
            Text("Add your provider credentials in Settings before browsing \(screenTitle.lowercased()).")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Configure Provider") {
                isPresentingSettings = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func browseTile(for item: SearchResultItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VideoTile(video: item.video)
                .frame(height: 240)
                .clipShape(.rect(cornerRadius: 8))

            Text(item.video.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private func loadCategories(force: Bool = false) async {
        do {
            state = .fetching
            coverageTask?.cancel()
            browseTask?.cancel()

            switch contentType {
            case .vod:
                try await catalog.getVodCategories(force: force)
            case .series:
                try await catalog.getSeriesCategories(force: force)
            case .live:
                break
            }
            state = .done
            if let selectedCategoryID, !categories.contains(where: { $0.id == selectedCategoryID }) {
                self.selectedCategoryID = nil
            }
            startCoverageIfNeeded()
            scheduleBrowseRefresh(debounced: false)
        } catch {
            logger.error("Failed to load \(contentType.rawValue, privacy: .public) categories: \(error.localizedDescription, privacy: .public)")
            state = .error(error)
        }
    }

    private func startCoverageIfNeeded() {
        guard contentType == .vod || contentType == .series else { return }
        coverageTask?.cancel()
        let scope: SearchMediaScope = contentType == .series ? .series : .movies
        searchProgress = SearchIndexProgress(indexedCategories: 0, totalCategories: 0, scope: scope)

        coverageTask = Task {
            for await progress in catalog.ensureSearchCoverage(scope: scope) {
                if Task.isCancelled { return }
                searchProgress = progress
                await performBrowseQuery()
            }
        }
    }

    private func scheduleBrowseRefresh(debounced: Bool = true) {
        browseTask?.cancel()
        browseTask = Task {
            if debounced {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            await performBrowseQuery()
        }
    }

    @MainActor
    private func performBrowseQuery() async {
        do {
            browseResults = try await catalog.search(
                SearchQuery(
                    text: queryText.trimmingCharacters(in: .whitespacesAndNewlines),
                    scope: searchScope,
                    filters: browseFilters,
                    sort: browseSort.searchSort
                )
            )
        } catch {
            browseResults = []
        }
    }

    private var browseFilters: SearchFilters {
        var filters = SearchFilters.default
        if let selectedCategoryID {
            filters.categoryIDs = [selectedCategoryID]
        }
        return filters
    }

    private var categories: [Category] {
        switch contentType {
        case .vod:
            catalog.vodCategories
        case .series:
            catalog.seriesCategories
        case .live:
            []
        }
    }

    private var searchScope: SearchMediaScope {
        switch contentType {
        case .vod:
            .movies
        case .series:
            .series
        case .live:
            .all
        }
    }

    private var selectedCategoryName: String {
        guard let selectedCategoryID,
              let category = categories.first(where: { $0.id == selectedCategoryID }) else {
            return "All Categories"
        }
        return category.name
    }

    private var isIndexing: Bool {
        searchProgress.totalCategories > 0 && !searchProgress.isComplete
    }

    private var emptyBrowseMessage: String {
        if let selectedCategoryID,
           let category = categories.first(where: { $0.id == selectedCategoryID }) {
            if queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "No titles are available in \(category.name)."
            }
            return "No titles match \"\(queryText)\" in \(category.name)."
        }

        if queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No titles match this category/filter combination."
        }

        return "No titles match \"\(queryText)\"."
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16, alignment: .top)]
    }

    private var screenTitle: String {
        switch contentType {
        case .vod:
            "Movies"
        case .series:
            "Series"
        case .live:
            "Live"
        }
    }

    private var emptyCatalogMessage: String {
        switch contentType {
        case .vod:
            "No movies were returned by the provider."
        case .series:
            "No series were returned by the provider."
        case .live:
            "No channels were returned by the provider."
        }
    }
}

#Preview(traits: .previewData, .fixedLayout(width: 1000, height: 500)) {
    MoviesScreen()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
