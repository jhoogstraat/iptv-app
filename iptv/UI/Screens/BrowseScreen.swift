//
//  MoviesScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import SQLiteData

enum BrowseSort: String, CaseIterable, Identifiable {
    case title, newest, rating
    var id: Self { self }
}

//private func streamSortDescriptors(for browseSort: BrowseSort) -> [SortDescriptor<Movie>] {
//    switch browseSort {
//    case .title:
//        [
//            SortDescriptor(\Movie.name, order: .forward),
//            SortDescriptor(\Movie.rating, order: .reverse),
//            SortDescriptor(\Movie.added, order: .reverse),
//            SortDescriptor(\Movie.sourceId, order: .forward)
//        ]
//    case .newest:
//        [
//            SortDescriptor(\Movie.added, order: .reverse),
//            SortDescriptor(\Movie.rating, order: .reverse),
//            SortDescriptor(\Movie.name, order: .forward),
//            SortDescriptor(\Movie.sourceId, order: .forward)
//        ]
//    case .rating:
//        [
//            SortDescriptor(\Movie.rating, order: .reverse),
//            SortDescriptor(\Movie.added, order: .reverse),
//            SortDescriptor(\Movie.name, order: .forward),
//            SortDescriptor(\Movie.sourceId, order: .forward)
//        ]
//    }
//}

struct BrowseScreen: View {
    @State var type: MediaType = .movie
    @State var selectedCategory: Category.ID? = nil
    @State var queryText: String = ""
    @State var sort: BrowseSort = .title
   
    @Environment(ActiveSession.self) var session
    
    @FetchAll(Category.where { $0.type.eq(MediaType.movie) }) private var categories: [Category]
    
    var category: Category? { categories.first { $0.id == selectedCategory } }
    
    private var fallbackScreentitle: String {
        return switch type {
            case .movie:
                "Movies"
            case .series:
                "Series"
            default:
               "Content"
            }
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
                    category: $selectedCategory,
                    searchText: $queryText,
                    sort: $sort
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(fallbackScreentitle)
        .searchable(text: $queryText, prompt: "Search \(fallbackScreentitle)")
        .task {
            // TODO: Find last selected category and reopen
            if selectedCategory == nil, let id = categories.first?.id {
                selectedCategory = id
            }
        }
        .task(id: selectedCategory) {
            // Fetch media for category if not yet initialized
            guard let category, category.updatedAt == nil else {
                return
            }
            
            do {
                try await session.syncManager.updateMovies(in: category.id)
            } catch is CancellationError {
                print("Cancelled update movies task")
            } catch {
                fatalError("\(error.localizedDescription), \(#file) \(#line) - \(#function) - \(#column) - \(#fileID)")
            }
        }
        .toolbar {
            Spacer()
            
            Menu(category?.title ?? "") {
                ForEach(categories) { category in
                    Button(category.title) {
                        selectedCategory = category.id
                    }
                }
            }
            .buttonStyle(.plain)
            
//            ToolbarItem(placement: .primaryAction) {
//                sortMenu
//            }
        }
//                .withBackgroundActivityToolbar()
//        .toolbar {
////                    let groups = Dictionary(grouping: categories) { $0.group }.map { (key: $0.key, categories: $0.value) }
//            ToolbarItem(placement: .principal) {
//                Menu {
//                    ForEach(categories) { category in
//                        Button(category.title) {
//                            selectedCategory = category
//                        }
//                    }
////                                if let title = categoryGroup.key {
////                                    Section(title) {
////                                        CategorySelector(selectedCategory: $selectedCategory, categories: categoryGroup.categories)
////                                    }
////                                } else {
////                            CategorySelector(selectedCategory: $selectedCategory, categories: categories)
////                                }
////                            }
//                }
////                        label: {
////                            categorySelectorLabel(title: selectedCategory?.name ?? fallbackScreentitle)
////                        }
//                .buttonStyle(.plain)
//                .help("Category: \(selectedCategory?.name ?? "No Category Selected")")
//            }

//            ToolbarItem(placement: .primaryAction) {
//                sortMenu
//            }
//        }
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

//    private func reconcileSelection() {
//        guard !categories.isEmpty else {
//            selectedCategory = nil
//            return
//        }
//
//        if let selectedCategory, categories.contains(where: { $0.id == selectedCategory }) {
//            return
//        }
//
//        selectedCategory = categories.first
//    }

}

private struct CoverGrid: View {
    private enum BrowseLayout {
        static let standardPosterWidth: CGFloat = 170
        static let minimumPosterWidth: CGFloat = 150
        static let posterAspectRatio: CGFloat = 2 / 3
    }
    
    @Binding var category: Category.ID?
    @Binding var searchText: String
    @Binding var sort: BrowseSort
    
    @State private var error: String?
   
    @State @FetchAll var media: [Media] = []
    
    var body: some View {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                    ForEach(media) { media in
                        print(media.categoryID)
                        return NavigationLink {
                            ContentUnavailableView("Not yet implemented", systemImage: "fail")
//                            MovieDetailScreen(movie: movie)
                        } label: {
                            BrowsePosterTile(media: media)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .task(id: [category, searchText, sort] as [AnyHashable]) {
                await updateQuery()
            }
        }
    
    private func updateQuery() async {
       do {
           try await $media.wrappedValue.load(
           Media
            .where { $0.categoryID.eq(category) }
//             .order {
//               if order == .forward {
//                 $0.timestamp
//               } else {
//                 $0.timestamp.desc()
//               }
//             }
         )
       } catch {
         // Handle error...
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
                
//                if let languageText = media.language {
//                    Text(languageText)
//                        .font(.footnote.weight(.semibold))
//                        .padding(.horizontal, 2)
//                        .padding(4)
//                        .background(.thinMaterial)
//                        .clipShape(.rect(cornerRadius: 8))
//                }
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

struct CategorySelector: View {
    @Binding var selectedCategory: Category?
    
    @FetchAll(Category.where { $0.type.eq(MediaType.movie) }) var categories: [Category]
    
    var body: some View {
        ForEach(categories) { category in
            Text(category.title)
//            Button {
//                selectedCategory = category
//            } label: {
//                if category == selectedCategory {
//                    Label(category.name, systemImage: "checkmark")
//                } else {
//                    Text(category.name)
//                }
//            }
        }
    }
}

#Preview {
    let _ = prepareDependencies {
        $0.defaultDatabase = try! appDatabase()
    }
    BrowseScreen()
}
