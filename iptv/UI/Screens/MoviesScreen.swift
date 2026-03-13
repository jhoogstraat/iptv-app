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

    @Environment(AppContainer.self) private var appContainer
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

            await viewModel?.load(policy: .cachedThenRefresh)
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
                        Task { await viewModel.load(policy: .refreshNow) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

            case .done:
                if viewModel.categories.isEmpty {
                    VStack(spacing: 12) {
                        Text(emptyCatalogMessage)
                        Button("Refresh") {
                            Task { await viewModel.load(policy: .refreshNow) }
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
                                    ForEach(viewModel.browseResults) { item in
                                        NavigationLink {
                                            destination(for: item, viewModel: viewModel)
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
            categorySelectorLabel(title: navigationBarTitle(for: viewModel))
        }
        .buttonStyle(.plain)
        .help("Category: \(selectedCategoryName(for: viewModel))")
    }

    @ViewBuilder
    private func categorySelectorLabel(title: String) -> some View {
        #if os(macOS)
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .padding(.horizontal, categorySelectorHorizontalPadding)
            .padding(.vertical, categorySelectorVerticalPadding)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
        #else
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .padding(.horizontal, categorySelectorHorizontalPadding)
            .padding(.vertical, categorySelectorVerticalPadding)
        #endif
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

    private func destination(for item: MoviesBrowseItem, viewModel: MoviesScreenViewModel) -> some View {
        guard let video = viewModel.video(for: item) else {
            return AnyView(
                ScopedPlaceholderView(
                    title: "Title Unavailable",
                    message: "The selected item is no longer available in the current category."
                )
                .navigationTitle(item.title)
            )
        }

        switch contentType {
        case .vod:
            return AnyView(MovieDetailScreen(video: video))
        case .series:
            return AnyView(
                EpisodeDetailTile(video: video)
                    .navigationTitle(video.name)
            )
        case .live:
            return AnyView(
                ScopedPlaceholderView(
                    title: "Live Episodes Are Unavailable",
                    message: "Episode detail only applies to series content."
                )
                .navigationTitle(video.name)
            )
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
                Text("Configure Provider")
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

    private func browseTile(for item: MoviesBrowseItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BrowsePosterTile(item: item)
                .aspectRatio(BrowseLayout.posterAspectRatio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))

            Text(item.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private func ensureViewModel() {
        if viewModel == nil {
            viewModel = appContainer.makeMoviesViewModel(contentType: contentType)
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

    private var categorySelectorHorizontalPadding: CGFloat {
        #if os(macOS)
        18
        #else
        10
        #endif
    }

    private var categorySelectorVerticalPadding: CGFloat {
        #if os(macOS)
        6
        #else
        4
        #endif
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

private struct BrowsePosterTile: View {
    let item: MoviesBrowseItem

    var body: some View {
        ZStack(alignment: .top) {
            artwork
            badgeRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.12))
        .clipShape(.rect(cornerRadius: 8))
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: item.artworkURL) { phase in
            if let image = phase.image {
                image.boundedCoverArtwork()
            } else if phase.error != nil {
                VStack {
                    Spacer()
                    Text(item.title)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var badgeRow: some View {
        HStack {
            if let ratingText = item.ratingText {
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

            if let languageText = item.languageText {
                Text(languageText)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 2)
                    .padding(4)
                    .background(.thinMaterial)
                    .clipShape(.rect(cornerRadius: 8))
            }
        }
        .padding(6)
    }
}

#Preview(traits: .previewData, .fixedLayout(width: 1000, height: 500)) {
    MoviesScreen()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
