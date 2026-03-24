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

struct BrowseScreen: View {
    @Environment(SessionManager.self) private var sessionManager

    let type: MediaType
    let presentProviderSetup: () -> Void

    init(type: MediaType = .movie, presentProviderSetup: @escaping () -> Void = {}) {
        self.type = type
        self.presentProviderSetup = presentProviderSetup
    }

    private var screenTitle: String {
        return switch type {
            case .movie:
                "Movies"
            case .series:
                "Series"
            default:
               "Content"
        }
    }
    
    var body: some View {
        Group {
            if sessionManager.hasActiveSession {
                ProviderBrowseContent(type: type)
            } else {
                ContentUnavailableView {
                    Label("Quite empty in here", systemImage: "tray")
                } description: {
                    Text("Add a provider to start syncing your library and browse movies.")
                } actions: {
                    Button("Add Provider", action: presentProviderSetup)
                        .buttonStyle(.borderedProminent)
                }
                .navigationTitle(screenTitle)
            }
        }
    }
}

private struct ProviderBrowseContent: View {
    @Environment(ActiveSession.self) private var session

    let type: MediaType

    @State private var selectedCategoryID: Category.ID?
    @State private var searchText = ""
    @State private var sort: BrowseSort = .title

    @FetchAll(Category.where { $0.type.eq(MediaType.movie) })
    private var categories: [Category]

    private var category: Category? { categories.first { $0.id == selectedCategoryID } }

    private var groups: Array<(key: String, value: [Category])> {
        Dictionary(grouping: categories) { element in
            if let match = element.title.firstMatch(of: #/\|(.*)\|(.*)/#) {
                return String(match.output.1)
            } else {
                return "  "
            }
        }.sorted(by: { $0.key < $1.key })
    }

    private var fallbackScreenTitle: String {
        if let category {
            return category.title
        }

        return switch type {
            case .movie:
                "Movies"
            case .series:
                "Series"
            default:
                "Content"
        }
    }

    var body: some View {
        Group {
            if categories.isEmpty {
                ContentUnavailableView {
                    Text("No movies available")
                } description: {
                    Text("The configured provider did not return any movies.")
                }
            } else if let selectedCategoryID {
                CoverGridSection(selectedCategoryID: selectedCategoryID, sort: sort, filter: searchText)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(fallbackScreenTitle)
        .searchable(text: $searchText, prompt: "Search \(fallbackScreenTitle)")
        .task {
            if selectedCategoryID == nil, let id = categories.first?.id {
                selectedCategoryID = id
            }
        }
        .task(id: selectedCategoryID) {
            guard let category, category.updatedAt == nil else {
                return
            }

            do {
                try await session.syncManager.updateMovies(in: category.id)
            } catch is CancellationError {
                print("Cancelled update movies task")
            } catch {
                assertionFailure("Failed to update movies: \(error.localizedDescription)")
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(groups, id: \.key) { group in
                        Section(group.key) {
                            ForEach(group.value, id: \.id) { category in
                                Button(category.title) {
                                    withAnimation(.interpolatingSpring(duration: 0.22)) {
                                        selectedCategoryID = category.id
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Label(category?.title ?? "Category", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}

struct CoverGridSection: View {
    let selectedCategoryID: Category.ID
    let sort: BrowseSort
    let filter: String
   
    @FetchAll private var media: [Media]
    
    init(selectedCategoryID: Category.ID, sort: BrowseSort, filter: String) {
        self.selectedCategoryID = selectedCategoryID
        self.sort = sort
        self.filter = filter
        
        _media = FetchAll(Media.where {
            $0.categoryID.eq(selectedCategoryID)
                .and($0.title.contains(filter))
        })
    }
    
    var body: some View {
        CoverGrid(media: media)
            .id(selectedCategoryID)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

private struct CoverGrid: View {
    private enum BrowseLayout {
        static let standardPosterWidth: CGFloat = 170
        static let minimumPosterWidth: CGFloat = 150
        static let posterAspectRatio: CGFloat = 2 / 3
    }
    
    let media: [Media]
    
    var body: some View {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                    if media.isEmpty {
                        ForEach(0..<10) { idx in
                            BrowseSkeletonTile()
                        }
                    } else {
                        ForEach(media) { media in
                            NavigationLink {
                                ContentUnavailableView("Not yet implemented", systemImage: "film")
    //                            MovieDetailScreen(movie: movie)
                            } label: {
                                BrowsePosterTile(media: media)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
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
                    BrowseSkeletonTile()
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
