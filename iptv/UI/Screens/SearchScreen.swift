//
//  SearchScreen.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import SwiftUI

struct SearchScreen: View {
    @Environment(Catalog.self) private var catalog
    @Environment(ProviderStore.self) private var providerStore
    @Environment(FavoritesStore.self) private var favoritesStore

    @State private var viewModel: SearchScreenViewModel?
    @State private var isShowingFilters = false

    private var queryBinding: Binding<String> {
        Binding(
            get: { viewModel?.queryText ?? "" },
            set: { newValue in
                viewModel?.queryText = newValue
                viewModel?.scheduleSearch()
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if !providerStore.hasConfiguration {
                    missingProviderView
                } else if let viewModel {
                    content(for: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Search")
            .toolbar {
                if providerStore.hasConfiguration, let viewModel {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isShowingFilters = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }

                    ToolbarItem(placement: .automatic) {
                        Menu {
                            Picker("Sort", selection: sortBinding(for: viewModel)) {
                                ForEach(SearchSort.allCases, id: \.self) { sort in
                                    Text(sort.displayName).tag(sort)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                }
            }
            .searchable(text: queryBinding, placement: .automatic, prompt: "Search movies and series")
            .sheet(isPresented: $isShowingFilters) {
                if let viewModel {
                    SearchFiltersSheet(viewModel: viewModel)
                }
            }
            .task(id: providerStore.revision) {
                ensureViewModel()
                viewModel?.start()
            }
        }
    }

    @ViewBuilder
    private func content(for viewModel: SearchScreenViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.indexProgress.totalCategories > 0 && !viewModel.indexProgress.isComplete {
                Text("Indexing \(viewModel.indexProgress.indexedCategories)/\(viewModel.indexProgress.totalCategories) categories")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            if !activeFilterLabels(for: viewModel).isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(activeFilterLabels(for: viewModel), id: \.self) { label in
                            Text(label)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.gray.opacity(0.25))
                                .clipShape(.capsule)
                        }
                    }
                    .padding(.horizontal)
                }
                .scrollIndicators(.never)
            }

            switch viewModel.phase {
            case .idle:
                ContentUnavailableView(
                    "Search Movies and Series",
                    systemImage: "magnifyingglass",
                    description: Text("Type a title or apply filters to start searching.")
                )
            case .loading:
                if viewModel.results.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    resultsList(viewModel)
                }
            case .loaded:
                if viewModel.results.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "film",
                        description: Text("Try a different query or change filters.")
                    )
                } else {
                    resultsList(viewModel)
                }
            case .failed(let error):
                VStack(spacing: 12) {
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        viewModel.scheduleSearch(debounced: false)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func resultsList(_ viewModel: SearchScreenViewModel) -> some View {
        List {
            ForEach(viewModel.results) { item in
                NavigationLink {
                    destination(for: item.video)
                } label: {
                    SearchResultRowView(item: item, isFavorite: viewModel.isFavorite(item))
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        Task { await toggleFavorite(video: item.video, currentlyFavorite: viewModel.isFavorite(item), viewModel: viewModel) }
                    } label: {
                        Label(viewModel.isFavorite(item) ? "Unfavorite" : "Favorite", systemImage: viewModel.isFavorite(item) ? "heart.slash" : "heart")
                    }
                    .tint(viewModel.isFavorite(item) ? .gray : .pink)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func destination(for video: Video) -> some View {
        switch video.xtreamContentType {
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
            Text("Add provider credentials in Settings to use search.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            #if os(macOS)
            SettingsLink {
                Text("Configure Provider")
            }
                .buttonStyle(.borderedProminent)
            #endif
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ensureViewModel() {
        if viewModel == nil {
            viewModel = SearchScreenViewModel(
                catalog: catalog,
                providerStore: providerStore,
                favoritesStore: favoritesStore
            )
        }
    }

    private func sortBinding(for viewModel: SearchScreenViewModel) -> Binding<SearchSort> {
        Binding(
            get: { viewModel.sort },
            set: { newValue in
                viewModel.sort = newValue
                viewModel.scheduleSearch(debounced: false)
            }
        )
    }

    private func activeFilterLabels(for viewModel: SearchScreenViewModel) -> [String] {
        var labels: [String] = []
        labels.append("Scope: \(viewModel.scope.displayName)")
        labels.append("Sort: \(viewModel.sort.displayName)")
        if let minRating = viewModel.filters.minRating {
            labels.append("Min rating \(minRating.formatted(.number.precision(.fractionLength(1))))")
        }
        if let maxRating = viewModel.filters.maxRating {
            labels.append("Max rating \(maxRating.formatted(.number.precision(.fractionLength(1))))")
        }
        if viewModel.filters.addedWindow != .any {
            labels.append(viewModel.filters.addedWindow.displayName)
        }
        labels.append(contentsOf: viewModel.filters.genres.map { "Genre: \($0)" })
        labels.append(contentsOf: viewModel.filters.languages.map { "Language: \($0)" })
        return labels
    }

    private func toggleFavorite(video: Video, currentlyFavorite: Bool, viewModel: SearchScreenViewModel) async {
        guard let config = try? providerStore.requiredConfiguration() else { return }
        let fingerprint = ProviderCacheFingerprint.make(from: config)
        await favoritesStore.setFavorite(video: video, providerFingerprint: fingerprint, isFavorite: !currentlyFavorite)
        await MainActor.run {
            viewModel.start()
        }
    }
}

private struct SearchFiltersSheet: View {
    @Bindable var viewModel: SearchScreenViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Scope") {
                    Picker("Content", selection: scopeBinding) {
                        ForEach(SearchMediaScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Rating") {
                    Toggle("Minimum rating", isOn: minRatingEnabledBinding)
                    if viewModel.filters.minRating != nil {
                        Slider(
                            value: minRatingValueBinding,
                            in: 0...10,
                            step: 0.5
                        ) {
                            Text("Min rating")
                        }
                        Text(viewModel.filters.minRating?.formatted(.number.precision(.fractionLength(1))) ?? "0.0")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Maximum rating", isOn: maxRatingEnabledBinding)
                    if viewModel.filters.maxRating != nil {
                        Slider(
                            value: maxRatingValueBinding,
                            in: 0...10,
                            step: 0.5
                        ) {
                            Text("Max rating")
                        }
                        Text(viewModel.filters.maxRating?.formatted(.number.precision(.fractionLength(1))) ?? "10.0")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Added") {
                    Picker("Window", selection: $viewModel.filters.addedWindow) {
                        ForEach(SearchAddedWindow.allCases, id: \.self) { window in
                            Text(window.displayName).tag(window)
                        }
                    }
                }

                if !viewModel.availableGenres.isEmpty {
                    Section("Genres") {
                        ForEach(viewModel.availableGenres, id: \.self) { genre in
                            Toggle(genre, isOn: genreBinding(for: genre))
                        }
                    }
                }

                if !viewModel.availableLanguages.isEmpty {
                    Section("Languages") {
                        ForEach(viewModel.availableLanguages, id: \.self) { language in
                            Toggle(language, isOn: languageBinding(for: language))
                        }
                    }
                }

                Section("Actions") {
                    Button("Clear Filters") {
                        viewModel.clearFilterSelections()
                    }
                    Button("Apply") {
                        viewModel.scheduleSearch(debounced: false)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var scopeBinding: Binding<SearchMediaScope> {
        Binding(
            get: { viewModel.scope },
            set: { newScope in
                viewModel.setScope(newScope)
            }
        )
    }

    private var minRatingEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.filters.minRating != nil },
            set: { enabled in
                viewModel.filters.minRating = enabled ? 5.0 : nil
            }
        )
    }

    private var minRatingValueBinding: Binding<Double> {
        Binding(
            get: { viewModel.filters.minRating ?? 5.0 },
            set: { newValue in
                viewModel.filters.minRating = newValue
            }
        )
    }

    private var maxRatingEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.filters.maxRating != nil },
            set: { enabled in
                viewModel.filters.maxRating = enabled ? 8.0 : nil
            }
        )
    }

    private var maxRatingValueBinding: Binding<Double> {
        Binding(
            get: { viewModel.filters.maxRating ?? 8.0 },
            set: { newValue in
                viewModel.filters.maxRating = newValue
            }
        )
    }

    private func genreBinding(for genre: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.filters.genres.contains(genre) },
            set: { enabled in
                if enabled {
                    viewModel.filters.genres.insert(genre)
                } else {
                    viewModel.filters.genres.remove(genre)
                }
            }
        )
    }

    private func languageBinding(for language: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.filters.languages.contains(language) },
            set: { enabled in
                if enabled {
                    viewModel.filters.languages.insert(language)
                } else {
                    viewModel.filters.languages.remove(language)
                }
            }
        )
    }
}

#Preview(traits: .previewData) {
    SearchScreen()
}
