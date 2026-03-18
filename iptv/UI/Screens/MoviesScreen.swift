//
//  MoviesScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import SwiftData

enum BrowseSort: String, CaseIterable, Identifiable {
    case title, newest, rating
    var id: Self { self }
}

private func streamSortDescriptors(for browseSort: BrowseSort) -> [SortDescriptor<Movie>] {
    switch browseSort {
    case .title:
        [
            SortDescriptor(\Movie.name, order: .forward),
            SortDescriptor(\Movie.rating, order: .reverse),
            SortDescriptor(\Movie.added, order: .reverse),
            SortDescriptor(\Movie.sourceId, order: .forward)
        ]
    case .newest:
        [
            SortDescriptor(\Movie.added, order: .reverse),
            SortDescriptor(\Movie.rating, order: .reverse),
            SortDescriptor(\Movie.name, order: .forward),
            SortDescriptor(\Movie.sourceId, order: .forward)
        ]
    case .rating:
        [
            SortDescriptor(\Movie.rating, order: .reverse),
            SortDescriptor(\Movie.added, order: .reverse),
            SortDescriptor(\Movie.name, order: .forward),
            SortDescriptor(\Movie.sourceId, order: .forward)
        ]
    }
}

struct BrowseScreen: View {
    @State var selectedCategory: MovieCategory?
    @State var queryText: String
    @State var sort: BrowseSort

    @Environment(SessionManager.self) private var sessionManager

    @Query private var categories: [MovieCategory]
    
    init() {
        self.queryText = ""
        self.sort = .title
        
//        _categoryRecords = Query(
//            filter: #Predicate<PersistedCategoryRecord> { record in
//                record.providerFingerprint == provider &&
//                record.contentType == contentType.rawValue
//            },
//            sort: [
//                SortDescriptor(\PersistedCategoryRecord.sortIndex, order: .forward),
//                SortDescriptor(\PersistedCategoryRecord.name, order: .forward)
//            ]
//        )
    }

    private var screenTitle: String {
        return "TODO"
//        switch contentType {
//        case .vod:
//            "Movies"
//        case .series:
//            "Series"
//        case .live:
//            "Live"
//        }
    }

//    private var emptyCatalogMessage: String {
//        switch contentType {
//        case .vod:
//            "No movies were returned by the provider."
//        case .series:
//            "No series were returned by the provider."
//        case .live:
//            "No channels were returned by the provider."
//        }
//    }

    var body: some View {
        NavigationStack {
            if categories.isEmpty {
                ContentUnavailableView {
                    Text("No movies available")
                } description: {
                    Text("The configured provider did not return any movies.")
                }
            } else if let selectedCategory {
                CoverGrid(
                    category: selectedCategory,
                    queryText: queryText,
                    sort: sort
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(screenTitle)
        .searchable(text: $queryText, prompt: "Search \(screenTitle)")
//        .withBackgroundActivityToolbar()
        .toolbar {
            var groups = Dictionary(grouping: categories) { $0.group }.map { (key: $0.key, categories: $0.value) }
            
            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(groups, id: \.key) { categoryGroup in
                        if let title = categoryGroup.key {
                            Section(title) {
                                CategorySelector(selectedCategory: $selectedCategory, categories: categoryGroup.categories)
                            }
                        } else {
                            CategorySelector(selectedCategory: $selectedCategory, categories: categoryGroup.categories)
                        }
                    }
                } label: {
                    categorySelectorLabel(title: selectedCategory?.name ?? screenTitle)
                }
                .buttonStyle(.plain)
                .help("Category: \(selectedCategory?.name ?? "No Category Selected")")
            }

            ToolbarItem(placement: .primaryAction) {
                sortMenu
            }
        }
    }

    struct CategorySelector: View {
        @Binding var selectedCategory: MovieCategory?
        
        let categories: [MovieCategory]
        
        var body: some View {
            ForEach(categories) { category in
                Button {
                    selectedCategory = category
                } label: {
                    if category == selectedCategory {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
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
            Picker("Sort", selection: $sort) {
                ForEach(BrowseSort.allCases) { sort in
                    Text(sort.rawValue)
                        .tag(sort)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .help("Sort: \(sort.rawValue)")
    }

    private func reconcileSelection() {
        guard !categories.isEmpty else {
            selectedCategory = nil
            return
        }

        if let selectedCategory, categories.contains(where: { $0 == selectedCategory }) {
            return
        }

        selectedCategory = categories.first
    }

}

private struct CoverGrid: View {
    private enum BrowseLayout {
        static let standardPosterWidth: CGFloat = 170
        static let minimumPosterWidth: CGFloat = 150
        static let posterAspectRatio: CGFloat = 2 / 3
    }
    
    let category: MovieCategory
    let queryText: String
    let sort: BrowseSort
    
    @State private var isLoading = true
    @State private var error: String?
    
    init(
        category: MovieCategory,
        queryText: String,
        sort: BrowseSort
    ) {
        self.category = category
        self.queryText = queryText
        self.sort = sort
    }
    
    var body: some View {
        if let errorMessage = error {
            VStack(spacing: 12) {
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                Button("Retry Category") {
                    print("TODO")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if isLoading {
            ScrollView {
                BrowseSkeletonGrid(columns: gridColumns)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        } else if category.movies.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "film",
                description: Text("No titles are available in this category")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                    ForEach(category.movies) { movie in
                        NavigationLink {
                            MovieDetailScreen(movie: movie)
                        } label: {
                            BrowsePosterTile(media: movie)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
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
                
                Text(media.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        
        @ViewBuilder
        private var artwork: some View {
            AsyncImage(url: media.coverImageURL) { phase in
                if let image = phase.image {
                    image.boundedCoverArtwork()
                } else if phase.error != nil {
                    VStack {
                        Spacer()
                        Text(media.name)
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
                
                if let languageText = media.language {
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
}
#Preview(traits: .previewData, .fixedLayout(width: 1000, height: 500)) {
    BrowseScreen()
}
