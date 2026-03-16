//
//  MoviesScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import SwiftData

struct ObservedCategoryRow: Identifiable, Hashable {
    let id: String
    let name: String
    let groupedDisplayName: String
    let languageGroupCode: String?

    init(
        id: String,
        name: String,
        groupedDisplayName: String,
        languageGroupCode: String?
    ) {
        self.id = id
        self.name = name
        self.groupedDisplayName = groupedDisplayName
        self.languageGroupCode = languageGroupCode
    }

    init(record: PersistedCategoryRecord) {
        let tagged = LanguageTaggedText(record.name)
        self.id = record.categoryID
        self.name = record.name
        self.groupedDisplayName = tagged.groupedDisplayName
        self.languageGroupCode = tagged.languageCode
    }

    func asCategory() -> Category {
        Category(id: id, name: name)
    }
}

struct ObservedStreamRow: Identifiable, Hashable {
    let id: Int
    let title: String
    let normalizedTitle: String
    let artworkURL: URL?
    let ratingText: String?
    let languageText: String?
    let containerExtension: String
    let contentType: String
    let coverImageURL: String?
    let tmdbId: String?
    let rating: Double?
    let addedAtRaw: String?

    init(
        id: Int,
        title: String,
        normalizedTitle: String,
        artworkURL: URL?,
        ratingText: String?,
        languageText: String?,
        containerExtension: String,
        contentType: String,
        coverImageURL: String?,
        tmdbId: String?,
        rating: Double?,
        addedAtRaw: String?
    ) {
        self.id = id
        self.title = title
        self.normalizedTitle = normalizedTitle
        self.artworkURL = artworkURL
        self.ratingText = ratingText
        self.languageText = languageText
        self.containerExtension = containerExtension
        self.contentType = contentType
        self.coverImageURL = coverImageURL
        self.tmdbId = tmdbId
        self.rating = rating
        self.addedAtRaw = addedAtRaw
    }

    init(record: PersistedStreamRecord) {
        let resolvedLanguage = record.language ?? LanguageTaggedText(record.name).languageCode

        self.id = record.videoID
        self.title = record.name
        self.normalizedTitle = record.normalizedTitle.isEmpty
            ? normalizedBrowseText(record.name)
            : record.normalizedTitle
        self.artworkURL = record.coverImageURL.flatMap(URL.init(string:))
        self.ratingText = record.rating.map {
            $0.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
        }
        self.languageText = resolvedLanguage
        self.containerExtension = record.containerExtension
        self.contentType = record.playbackContentType
        self.coverImageURL = record.coverImageURL
        self.tmdbId = record.tmdbId
        self.rating = record.rating
        self.addedAtRaw = record.addedAtRaw
    }

    func asVideo() -> Video {
        Video(
            id: id,
            name: title,
            containerExtension: containerExtension,
            contentType: contentType,
            coverImageURL: coverImageURL,
            tmdbId: tmdbId,
            rating: rating,
            addedAtRaw: addedAtRaw
        )
    }
}

struct MoviesCategoryMenuSection: Identifiable, Equatable {
    let title: String?
    let items: [MoviesCategoryMenuItem]

    var id: String {
        title ?? "__ungrouped__"
    }
}

struct MoviesCategoryMenuItem: Identifiable, Equatable {
    let category: ObservedCategoryRow
    let title: String

    var id: String {
        category.id
    }
}

func buildMoviesCategoryMenuSections(from categories: [ObservedCategoryRow]) -> [MoviesCategoryMenuSection] {
    var ungroupedItems: [MoviesCategoryMenuItem] = []
    var groupedItemsByLanguage: [String: [MoviesCategoryMenuItem]] = [:]
    var languageOrder: [String] = []

    for category in categories {
        let item = MoviesCategoryMenuItem(category: category, title: category.groupedDisplayName)

        guard let languageCode = category.languageGroupCode else {
            ungroupedItems.append(item)
            continue
        }

        if groupedItemsByLanguage[languageCode] == nil {
            languageOrder.append(languageCode)
        }
        groupedItemsByLanguage[languageCode, default: []].append(item)
    }

    var sections: [MoviesCategoryMenuSection] = []
    if !ungroupedItems.isEmpty {
        sections.append(MoviesCategoryMenuSection(title: nil, items: ungroupedItems))
    }

    for languageCode in languageOrder {
        guard let items = groupedItemsByLanguage[languageCode], !items.isEmpty else { continue }
        sections.append(MoviesCategoryMenuSection(title: languageCode, items: items))
    }

    return sections
}

func filterMoviesBrowseRows(_ rows: [ObservedStreamRow], queryText: String) -> [ObservedStreamRow] {
    let normalizedQuery = normalizedBrowseText(queryText)
    guard !normalizedQuery.isEmpty else { return rows }
    return rows.filter { $0.normalizedTitle.localizedCaseInsensitiveContains(normalizedQuery) }
}

private func normalizedBrowseText(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
}

private func streamSortDescriptors(for browseSort: BrowseSort) -> [SortDescriptor<PersistedStreamRecord>] {
    switch browseSort {
    case .title:
        [
            SortDescriptor(\PersistedStreamRecord.name, order: .forward),
            SortDescriptor(\PersistedStreamRecord.videoID, order: .forward)
        ]
    case .newest:
        [
            SortDescriptor(\PersistedStreamRecord.addedAt, order: .reverse),
            SortDescriptor(\PersistedStreamRecord.rating, order: .reverse),
            SortDescriptor(\PersistedStreamRecord.name, order: .forward),
            SortDescriptor(\PersistedStreamRecord.videoID, order: .forward)
        ]
    case .rating:
        [
            SortDescriptor(\PersistedStreamRecord.rating, order: .reverse),
            SortDescriptor(\PersistedStreamRecord.addedAt, order: .reverse),
            SortDescriptor(\PersistedStreamRecord.name, order: .forward),
            SortDescriptor(\PersistedStreamRecord.videoID, order: .forward)
        ]
    }
}

struct MoviesProviderRequestState: Equatable {
    var didRequestCategories = false
    var isLoadingCategories = false
    var categoryLoadErrorMessage: String?
    var requestedCategoryIDs: Set<String> = []
    var loadingCategoryIDs: Set<String> = []
    var categoryLoadErrors: [String: String] = [:]
}

struct BrowseScreen: View {
    let contentType: XtreamContentType

    @State var selectedCategoryID: String?
    @State var queryText: String
    @State var browseSort: BrowseSort = .title
    @State private var requestState: MoviesProviderRequestState = MoviesProviderRequestState()
    
    @Environment(ProviderStore.self) private var providerStore
    @Environment(Catalog.self) private var catalog

    @Query private var categoryRecords: [PersistedCategoryRecord]

    private var providerFingerprint: String
    
    init(_ contentType: XtreamContentType, provider: String) {
        self.contentType = contentType
        self.providerFingerprint = provider
        self.queryText = ""
        
        _categoryRecords = Query(
            filter: #Predicate<PersistedCategoryRecord> { record in
                record.providerFingerprint == provider &&
                record.contentType == contentType.rawValue
            },
            sort: [
                SortDescriptor(\PersistedCategoryRecord.sortIndex, order: .forward),
                SortDescriptor(\PersistedCategoryRecord.name, order: .forward)
            ]
        )
    }

    @MainActor
    private var categories: [ObservedCategoryRow] {
        categoryRecords.map(ObservedCategoryRow.init)
    }

    private var selectedCategory: ObservedCategoryRow? {
        guard let selectedCategoryID else { return nil }
        return categories.first { $0.id == selectedCategoryID }
    }

    private var categoryMenuSections: [MoviesCategoryMenuSection] {
        buildMoviesCategoryMenuSections(from: categories)
    }

    private var categoryIDs: [String] {
        categories.map(\.id)
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

    var body: some View {
        NavigationStack {
            if categories.isEmpty {
                categoriesEmptyState
            } else if let selectedCategory {
                MoviesObservedCategoryGrid(
                    providerFingerprint: providerFingerprint,
                    category: selectedCategory,
                    contentType: contentType,
                    queryText: queryText,
                    requestState: $requestState,
                    browseSort: browseSort
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(screenTitle)
        .searchable(text: $queryText, prompt: "Search \(screenTitle)")
        .withBackgroundActivityToolbar()
        .toolbar {
            if !categories.isEmpty {
                ToolbarItem(placement: .principal) {
                    categoryTitleMenu
                }

                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }
        }
        .task(id: "\(providerFingerprint)|\(contentType.rawValue)|categories:\(categories.isEmpty)") {
            if categories.isEmpty {
                await requestCategoriesIfNeeded(policy: .readThrough)
            }
        }
        .onChange(of: categoryIDs, initial: true) { _, _ in
            reconcileSelection()
        }
    }

    @ViewBuilder
    private var categoriesEmptyState: some View {
        if let categoryLoadErrorMessage = requestState.categoryLoadErrorMessage {
            VStack(spacing: 12) {
                Text(categoryLoadErrorMessage)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await requestCategories(policy: .forceRefresh) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        } else if requestState.isLoadingCategories || !requestState.didRequestCategories {
            ProgressView()
        } else {
            VStack(spacing: 12) {
                Text(emptyCatalogMessage)
                Button("Refresh") {
                    Task { await requestCategories(policy: .forceRefresh) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var categoryTitleMenu: some View {
        Menu {
            ForEach(categoryMenuSections) { section in
                if let title = section.title {
                    Section(title) {
                        categoryButtons(for: section.items)
                    }
                } else {
                    categoryButtons(for: section.items)
                }
            }
        } label: {
            categorySelectorLabel(title: selectedCategory?.name ?? screenTitle)
        }
        .buttonStyle(.plain)
        .help("Category: \(selectedCategory?.name ?? "No Category Selected")")
    }

    @ViewBuilder
    private func categoryButtons(for items: [MoviesCategoryMenuItem]) -> some View {
        ForEach(items) { item in
            Button {
                selectedCategoryID = item.category.id
            } label: {
                if item.category.id == selectedCategoryID {
                    Label(item.title, systemImage: "checkmark")
                } else {
                    Text(item.title)
                }
            }
        }
    }

    @ViewBuilder
    private func categorySelectorLabel(title: String) -> some View {
        #if os(macOS)
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        #endif
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

    private func reconcileSelection() {
        guard !categories.isEmpty else {
            selectedCategoryID = nil
            return
        }

        if let selectedCategoryID,
           categories.contains(where: { $0.id == selectedCategoryID }) {
            return
        }

        selectedCategoryID = categories.first?.id
    }

    private func requestCategoriesIfNeeded(policy: CatalogLoadPolicy) async {
        guard !requestState.isLoadingCategories else { return }
        if policy == .readThrough, requestState.didRequestCategories {
            return
        }
        await requestCategories(policy: policy)
    }

    private func requestCategories(policy: CatalogLoadPolicy) async {
        requestState.didRequestCategories = true
        requestState.isLoadingCategories = true
        requestState.categoryLoadErrorMessage = nil

        defer { requestState.isLoadingCategories = false }

        do {
            try await catalog.getCategories(for: contentType, policy: policy)
        } catch is CancellationError {
        } catch {
            requestState.categoryLoadErrorMessage = error.localizedDescription
        }
    }
}

private struct MoviesObservedCategoryGrid: View {
    private enum BrowseLayout {
        static let standardPosterWidth: CGFloat = 170
        static let minimumPosterWidth: CGFloat = 150
        static let posterAspectRatio: CGFloat = 2 / 3
    }

    let providerFingerprint: String
    let category: ObservedCategoryRow
    let contentType: XtreamContentType
    let queryText: String
    @Binding var requestState: MoviesProviderRequestState
    let browseSort: BrowseSort

    @Environment(Catalog.self) private var catalog

    @Query private var streamRecords: [PersistedStreamRecord]

    init(
        providerFingerprint: String,
        category: ObservedCategoryRow,
        contentType: XtreamContentType,
        queryText: String,
        requestState: Binding<MoviesProviderRequestState>,
        browseSort: BrowseSort
    ) {
        self.providerFingerprint = providerFingerprint
        self.category = category
        self.contentType = contentType
        self.queryText = queryText
        self._requestState = requestState
        self.browseSort = browseSort

        let fingerprint = providerFingerprint
        let contentTypeRawValue = contentType.rawValue
        let categoryID = category.id
        _streamRecords = Query(
            filter: #Predicate<PersistedStreamRecord> { record in
                record.providerFingerprint == fingerprint &&
                record.contentType == contentTypeRawValue &&
                record.categoryID == categoryID
            },
            sort: streamSortDescriptors(for: browseSort)
        )
    }

    var body: some View {
        content
            .task(id: "\(providerFingerprint)|\(category.id)|\(streamRecords.isEmpty)") {
                if streamRecords.isEmpty {
                    await requestStreamsIfNeeded(policy: .readThrough)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = requestState.categoryLoadErrors[category.id] {
            VStack(spacing: 12) {
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                Button("Retry Category") {
                    Task { await requestStreams(policy: .forceRefresh) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if isLoadingSelectedCategory {
            ScrollView {
                BrowseSkeletonGrid(columns: gridColumns)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        } else if streamRecords.isEmpty, !hasRequestedCategory {
            ScrollView {
                BrowseSkeletonGrid(columns: gridColumns)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        } else if filteredRows.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "film",
                description: Text(emptyBrowseMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                    ForEach(filteredRows) { row in
                        NavigationLink {
                            destination(for: row)
                        } label: {
                            browseTile(for: row)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }

    @MainActor
    private var filteredRows: [ObservedStreamRow] {
        filterMoviesBrowseRows(streamRecords.map(ObservedStreamRow.init), queryText: queryText)
    }

    private var isLoadingSelectedCategory: Bool {
        requestState.loadingCategoryIDs.contains(category.id)
    }

    private var hasRequestedCategory: Bool {
        requestState.requestedCategoryIDs.contains(category.id)
    }

    private var emptyBrowseMessage: String {
        let trimmedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return hasRequestedCategory
                ? "No titles are available in \(category.name)."
                : "Loading \(category.name)..."
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

    private func browseTile(for row: ObservedStreamRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BrowsePosterTile(item: row)
                .aspectRatio(BrowseLayout.posterAspectRatio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))

            Text(row.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private func destination(for row: ObservedStreamRow) -> some View {
        let video = row.asVideo()
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

    private func requestStreamsIfNeeded(policy: CatalogLoadPolicy) async {
        guard !isLoadingSelectedCategory else { return }
        if policy == .readThrough, hasRequestedCategory {
            return
        }
        await requestStreams(policy: policy)
    }

    private func requestStreams(policy: CatalogLoadPolicy) async {
        requestState.requestedCategoryIDs.insert(category.id)
        requestState.loadingCategoryIDs.insert(category.id)
        requestState.categoryLoadErrors[category.id] = nil

        defer { requestState.loadingCategoryIDs.remove(category.id) }

        do {
            try await catalog.getStreams(in: category.asCategory(), contentType: contentType, policy: policy)
        } catch is CancellationError {
        } catch {
            requestState.categoryLoadErrors[category.id] = error.localizedDescription
        }
    }
}

private struct BrowsePosterTile: View {
    let item: ObservedStreamRow

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

#Preview(traits: .previewData, .fixedLayout(width: 1000, height: 500)) {
    BrowseScreen(.vod, provider: "")
}
