//
//  MoviesScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI

struct MoviesScreen: View {
    private enum BrowseLayout {
        static let standardPosterWidth: CGFloat = 170
        static let minimumPosterWidth: CGFloat = 150
        static let posterAspectRatio: CGFloat = 2 / 3
    }

    let contentType: XtreamContentType

    @Environment(Catalog.self) private var catalog
    @Environment(ProviderStore.self) private var providerStore

    @State private var viewModel: MoviesScreenViewModel?
    @State private var isPresentingSettings = false

    init(contentType: XtreamContentType = .vod) {
        self.contentType = contentType
    }

    var body: some View {
        NavigationStack {
            Group {
                if !providerStore.hasConfiguration {
                    missingProviderView
                } else if let viewModel {
                    contentForState(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(screenTitle)
            .searchable(text: queryBinding, prompt: "Search \(screenTitle)")
            .toolbar {
                if providerStore.hasConfiguration, let viewModel, !viewModel.categories.isEmpty {
                    ToolbarItem(placement: .principal) {
                        categoryTitleMenu(viewModel)
                    }

                    ToolbarItem(placement: .primaryAction) {
                        sortMenu(viewModel)
                    }
                }
            }
            #if !os(macOS)
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
            #endif
        }
        .task(id: providerStore.revision) {
            ensureViewModel()

            guard providerStore.hasConfiguration else {
                viewModel?.reset()
                catalog.reset()
                return
            }

            await viewModel?.load(force: true)
        }
    }

    @ViewBuilder
    private func contentForState(_ viewModel: MoviesScreenViewModel) -> some View {
        switch viewModel.phase {
            case .idle, .fetching:
                ProgressView()

            case .error(let error):
                VStack(spacing: 12) {
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await viewModel.load(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

            case .done:
                if viewModel.categories.isEmpty {
                    VStack(spacing: 12) {
                        Text(emptyCatalogMessage)
                        Button("Refresh") {
                            Task { await viewModel.load(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if viewModel.browseResults.isEmpty {
                            ContentUnavailableView(
                                "No Results",
                                systemImage: "film",
                                description: Text(emptyBrowseMessage(for: viewModel))
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                                    ForEach(viewModel.browseResults) { video in
                                        NavigationLink {
                                            destination(for: video)
                                        } label: {
                                            browseTile(for: video)
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

    private func categoryTitleMenu(_ viewModel: MoviesScreenViewModel) -> some View {
        Menu {
            ForEach(viewModel.categoryMenuSections) { section in
                if let title = section.title {
                    Section(title) {
                        categoryButtons(
                            for: section.items,
                            selectedCategoryID: viewModel.selectedCategoryID,
                            viewModel: viewModel
                        )
                    }
                } else {
                    categoryButtons(
                        for: section.items,
                        selectedCategoryID: viewModel.selectedCategoryID,
                        viewModel: viewModel
                    )
                }
            }
        } label: {
            Text(navigationBarTitle(for: viewModel))
                .font(.headline)
                .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help("Category: \(selectedCategoryName(for: viewModel))")
    }

    @ViewBuilder
    private func categoryButtons(
        for items: [MoviesScreenViewModel.CategoryMenuItem],
        selectedCategoryID: String?,
        viewModel: MoviesScreenViewModel
    ) -> some View {
        ForEach(items) { item in
            Button {
                Task { await viewModel.selectCategory(id: item.category.id) }
            } label: {
                if item.category.id == selectedCategoryID {
                    Label(item.title, systemImage: "checkmark")
                } else {
                    Text(item.title)
                }
            }
        }
    }

    private func sortMenu(_ viewModel: MoviesScreenViewModel) -> some View {
        Menu {
            Section("Sort") {
                Text(viewModel.browseSort.displayName)
            }

            Picker("Sort", selection: sortBinding(for: viewModel)) {
                ForEach(BrowseSort.allCases, id: \.self) { sort in
                    Text(sort.displayName)
                        .tag(sort)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .help("Sort: \(viewModel.browseSort.displayName)")
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
            #if os(macOS)
            SettingsLink {
                Text("Open Settings")
            }
                .buttonStyle(.borderedProminent)
            #else
            Button("Configure Provider") {
                isPresentingSettings = true
            }
            .buttonStyle(.borderedProminent)
            #endif
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func browseTile(for video: Video) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VideoTile(video: video)
                .aspectRatio(BrowseLayout.posterAspectRatio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))

            Text(video.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private func ensureViewModel() {
        if viewModel == nil {
            viewModel = MoviesScreenViewModel(contentType: contentType, catalog: catalog)
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { viewModel?.queryText ?? "" },
            set: { newValue in
                viewModel?.queryText = newValue
            }
        )
    }

    private func selectedCategoryBinding(for viewModel: MoviesScreenViewModel) -> Binding<String?> {
        Binding(
            get: { viewModel.selectedCategoryID },
            set: { newValue in
                Task { await viewModel.selectCategory(id: newValue) }
            }
        )
    }

    private func sortBinding(for viewModel: MoviesScreenViewModel) -> Binding<BrowseSort> {
        Binding(
            get: { viewModel.browseSort },
            set: { newValue in
                viewModel.browseSort = newValue
            }
        )
    }

    private func selectedCategoryName(for viewModel: MoviesScreenViewModel) -> String {
        viewModel.selectedCategory?.name ?? "No Category Selected"
    }

    private func navigationBarTitle(for viewModel: MoviesScreenViewModel) -> String {
        viewModel.selectedCategory?.name ?? screenTitle
    }

    private func emptyBrowseMessage(for viewModel: MoviesScreenViewModel) -> String {
        guard let category = viewModel.selectedCategory else {
            return "No category is available."
        }

        let trimmedQuery = viewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return "No titles are available in \(category.name)."
        }

        return "No titles match \"\(trimmedQuery)\" in \(category.name)."
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
