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
    @State private var prefetchCoordinator = StreamPrefetchCoordinator()
    @State private var queryText = ""
    @State private var scopedResults: [SearchResultItem] = []
    @State private var scopedSearchTask: Task<Void, Never>?
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
                scheduleScopedSearch()
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
                prefetchCoordinator.stop()
                catalog.reset()
                coverageTask?.cancel()
                scopedSearchTask?.cancel()
                scopedResults = []
                return
            }

            await loadCategories(force: true)
        }
        .onDisappear {
            prefetchCoordinator.stop()
            coverageTask?.cancel()
            scopedSearchTask?.cancel()
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
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            if !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                scopedResultsSection
                            }
                            ForEach(categories) { category in
                                VideoTileRow(category: category, contentType: contentType)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .toolbar(.hidden)
                }
        }
    }

    @ViewBuilder
    private var scopedResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Search Results")
                    .font(.headline)
                Spacer()
                if searchProgress.totalCategories > 0, !searchProgress.isComplete {
                    Text("Indexing \(searchProgress.indexedCategories)/\(searchProgress.totalCategories)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            if scopedResults.isEmpty {
                Text("No matches for \"\(queryText)\"")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(scopedResults.prefix(20)) { item in
                    NavigationLink {
                        destination(for: item.video)
                    } label: {
                        SearchResultRowView(item: item, isFavorite: false)
                            .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func destination(for video: Video) -> some View {
        switch contentType {
        case .vod:
            MovieDetailScreen(video: video)
        case .series, .live:
            EpisodeDetailTile()
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

    private func loadCategories(force: Bool = false) async {
        do {
            state = .fetching
            switch contentType {
            case .vod:
                try await catalog.getVodCategories(force: force)
            case .series:
                try await catalog.getSeriesCategories(force: force)
            case .live:
                break
            }
            state = .done
            prefetchCoordinator.start(categories: categories, contentType: contentType, catalog: catalog)
            startCoverageIfNeeded()
            scheduleScopedSearch(debounced: false)
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
            }
        }
    }

    private func scheduleScopedSearch(debounced: Bool = true) {
        scopedSearchTask?.cancel()
        scopedSearchTask = Task {
            if debounced {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            await performScopedSearch()
        }
    }

    @MainActor
    private func performScopedSearch() async {
        let text = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            scopedResults = []
            return
        }
        do {
            let scope: SearchMediaScope = contentType == .series ? .series : .movies
            let query = SearchQuery(text: text, scope: scope, filters: .default, sort: .relevance)
            scopedResults = try await catalog.search(query)
        } catch {
            scopedResults = []
        }
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
