//
//  MovieDetailScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 08.09.25.
//

import SwiftUI

struct MediaDetailDestination: View {
    let media: Media
    let categoryTitle: String?

    init(media: Media, categoryTitle: String? = nil) {
        self.media = media
        self.categoryTitle = categoryTitle
    }

    var body: some View {
        switch media.type {
        case .movie:
            MovieDetailScreen(movie: media, categoryTitle: categoryTitle)
        case .series:
            SeriesDetailScreen(series: media, categoryTitle: categoryTitle)
        case .episode:
            EpisodeDetailTile(series: media, episode: media)
        case .live:
            ScopedPlaceholderView(
                title: "Live TV details unavailable",
                message: "Live channel details are not part of this local-data foundation workstream."
            )
        }
    }
}

struct MovieDetailScreen: View {
    let movie: Media
    let categoryTitle: String?

    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var playError: String?
    @State private var favoriteIsSelected = false

    init(movie: Media, categoryTitle: String? = nil) {
        self.movie = movie
        self.categoryTitle = categoryTitle
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 700
            let topInset = proxy.safeAreaInsets.top
            let heroHeight = min(max(proxy.size.height * 0.58, 430), 590)

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(availableWidth: proxy.size.width, height: heroHeight, topInset: topInset)

                        DetailContentLayout(isCompact: isCompact, availableWidth: proxy.size.width) {
                            section("Synopsis", text: synopsisText)
                            metadataSection
                            availabilitySection
                        }
                        .background(Color.black)
                    }
                }
                .background(Color.black)

                topControls(topInset: topInset)
            }
            .background(Color.black)
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle(movie.title)
        .detailNavigationChrome()
    }

    private func hero(availableWidth: CGFloat, height: CGFloat, topInset: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            DetailHeroBackdrop(
                artworkURL: movie.coverURL,
                height: height,
                topInset: topInset,
                collapseProgress: 0,
                scrollOffset: 0,
                artworkContentMode: .fill
            )

            VStack(alignment: .leading, spacing: DetailSpacing.md) {
                Text(categoryTitle ?? "Movie")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))

                Text(movie.title)
                    .font(.system(size: availableWidth < 420 ? 42 : 58, weight: .black, design: .rounded))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)

                metadataPills

                Text(synopsisText)
                    .font(.callout)
                    .lineSpacing(4)
                    .lineLimit(3)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: 680, alignment: .leading)

                actionRow

                if let playError {
                    Text(playError)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red.opacity(0.94))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.55), in: Capsule(style: .continuous))
                        .accessibilityLabel("Playback error: \(playError)")
                }
            }
            .padding(.horizontal, availableWidth < 700 ? 20 : 40)
            .padding(.bottom, DetailSpacing.xl)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .frame(height: height + topInset)
    }

    private var metadataPills: some View {
        HStack(spacing: DetailSpacing.xs) {
            DetailMetaPill("Movie", systemImage: "film")

            if let rating = movie.rating {
                DetailMetaPill(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
            }

            DetailMetaPill("Local library", systemImage: "externaldrive")
        }
    }

    private var actionRow: some View {
        HStack(spacing: DetailSpacing.sm) {
            Button {
                playError = nil
                player.load(movie, presentation: .fullWindow)
                playError = player.errorMessage
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DetailActionStyle(variant: .primary))

            Button {
                favoriteIsSelected.toggle()
            } label: {
                Label(favoriteIsSelected ? "Favorited" : "Favorite", systemImage: favoriteIsSelected ? "heart.fill" : "heart")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(DetailActionStyle(variant: .icon))
            .accessibilityLabel(favoriteIsSelected ? "Favorited locally" : "Mark favorite")
            .accessibilityHint("Persistent favorites are not available until the Favorites feature is migrated.")

            Button {} label: {
                Label("Download unavailable", systemImage: "arrow.down.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(DetailActionStyle(variant: .icon))
            .disabled(true)
            .accessibilityHint("Downloads are not available until offline state is migrated.")
        }
        .frame(maxWidth: 620)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.sm) {
            DetailSectionHeader(title: "Library Metadata")
            DetailMetadataGrid(rows: metadataRows)
        }
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.sm) {
            DetailSectionHeader(title: "Source and Downloads")
            Text("Playback resolves from the active Xtream provider using the synced source identifier. Download and favorite persistence will appear here when those feature stores are available.")
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.secondary)
        }
    }

    private var metadataRows: [DetailMetadataRow] {
        [
            DetailMetadataRow(label: "Type", value: "Movie"),
            DetailMetadataRow(label: "Category", value: categoryTitle),
            DetailMetadataRow(label: "Rating", value: movie.rating.map { $0.formatted(.number.precision(.fractionLength(1))) }),
            DetailMetadataRow(label: "TMDB", value: movie.tmdbID),
            DetailMetadataRow(label: "Source ID", value: String(movie.sourceID)),
            DetailMetadataRow(label: "Updated", value: movie.updatedAt.formatted(date: .abbreviated, time: .shortened))
        ]
    }

    private var synopsisText: String {
        "No synopsis is available in the synced library record yet."
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DetailSpacing.xs) {
            DetailSectionHeader(title: title)
            Text(text)
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.secondary)
        }
    }

    private func topControls(topInset: CGFloat) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(DetailActionStyle(variant: .icon))
            .accessibilityLabel("Back")

            Spacer()

            DetailCollapsedHeaderBar(
                title: movie.title,
                artworkURL: movie.coverURL,
                titleArtworkURL: nil,
                progress: 1
            )
        }
        .padding(.top, topInset + 10)
        .padding(.horizontal, 16)
    }
}

struct SeriesDetailScreen: View {
    private enum DetailTab: String, CaseIterable, Identifiable {
        case episodes = "Episodes"
        case details = "Details"

        var id: String { rawValue }
    }

    let series: Media
    let categoryTitle: String?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: DetailTab = .episodes

    init(series: Media, categoryTitle: String? = nil) {
        self.series = series
        self.categoryTitle = categoryTitle
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 700
            let topInset = proxy.safeAreaInsets.top
            let heroHeight = min(max(proxy.size.height * 0.54, 400), 560)

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(availableWidth: proxy.size.width, height: heroHeight, topInset: topInset)

                        DetailContentLayout(isCompact: isCompact, availableWidth: proxy.size.width) {
                            Picker("Series detail section", selection: $selectedTab) {
                                ForEach(DetailTab.allCases) { tab in
                                    Text(tab.rawValue).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)

                            switch selectedTab {
                            case .episodes:
                                episodesSection
                            case .details:
                                detailsSection
                            }
                        }
                        .background(Color.black)
                    }
                }
                .background(Color.black)

                topControls(topInset: topInset)
            }
            .background(Color.black)
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle(series.title)
        .detailNavigationChrome()
    }

    private func hero(availableWidth: CGFloat, height: CGFloat, topInset: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            DetailHeroBackdrop(
                artworkURL: series.coverURL,
                height: height,
                topInset: topInset,
                collapseProgress: 0,
                scrollOffset: 0,
                artworkContentMode: .fill
            )

            VStack(alignment: .leading, spacing: DetailSpacing.md) {
                Text(categoryTitle ?? "Series")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))

                Text(series.title)
                    .font(.system(size: availableWidth < 420 ? 40 : 56, weight: .black, design: .rounded))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)

                HStack(spacing: DetailSpacing.xs) {
                    DetailMetaPill("Series", systemImage: "tv")
                    if let rating = series.rating {
                        DetailMetaPill(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                    }
                    DetailMetaPill("Episodes pending", systemImage: "rectangle.stack")
                }

                Text("Episode metadata has not been synced for this series yet. The detail path keeps series collections separate from playable movie streams.")
                    .font(.callout)
                    .lineSpacing(4)
                    .lineLimit(3)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: 680, alignment: .leading)

                HStack(spacing: DetailSpacing.sm) {
                    Button {} label: {
                        Label("Select Episode", systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DetailActionStyle(variant: .primary))
                    .disabled(true)

                    Button {} label: {
                        Label("Favorite unavailable", systemImage: "heart")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(DetailActionStyle(variant: .icon))
                    .disabled(true)

                    Button {} label: {
                        Label("Download unavailable", systemImage: "arrow.down.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(DetailActionStyle(variant: .icon))
                    .disabled(true)
                }
                .frame(maxWidth: 620)
            }
            .padding(.horizontal, availableWidth < 700 ? 20 : 40)
            .padding(.bottom, DetailSpacing.xl)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .frame(height: height + topInset)
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.md) {
            HStack {
                DetailSectionHeader(title: "Episodes")
                Spacer()
                Menu("Season") {
                    Button("Season data unavailable") {}
                        .disabled(true)
                }
                .buttonStyle(DetailActionStyle(variant: .chip(selected: false)))
                .disabled(true)
            }

            ContentUnavailableView {
                Label("Episodes Not Synced", systemImage: "rectangle.stack.badge.person.crop")
            } description: {
                Text("This series route is ready for season and episode rows, but the local schema does not yet persist episode lists for a series.")
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.lg) {
            VStack(alignment: .leading, spacing: DetailSpacing.xs) {
                DetailSectionHeader(title: "Synopsis")
                Text("No series synopsis is available in the synced library record yet.")
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DetailSpacing.sm) {
                DetailSectionHeader(title: "Library Metadata")
                DetailMetadataGrid(rows: metadataRows)
            }
        }
    }

    private var metadataRows: [DetailMetadataRow] {
        [
            DetailMetadataRow(label: "Type", value: "Series"),
            DetailMetadataRow(label: "Category", value: categoryTitle),
            DetailMetadataRow(label: "Rating", value: series.rating.map { $0.formatted(.number.precision(.fractionLength(1))) }),
            DetailMetadataRow(label: "TMDB", value: series.tmdbID),
            DetailMetadataRow(label: "Source ID", value: String(series.sourceID)),
            DetailMetadataRow(label: "Updated", value: series.updatedAt.formatted(date: .abbreviated, time: .shortened))
        ]
    }

    private func topControls(topInset: CGFloat) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(DetailActionStyle(variant: .icon))
            .accessibilityLabel("Back")

            Spacer()

            DetailCollapsedHeaderBar(
                title: series.title,
                artworkURL: series.coverURL,
                titleArtworkURL: nil,
                progress: 1
            )
        }
        .padding(.top, topInset + 10)
        .padding(.horizontal, 16)
    }
}

struct DetailMetadataRow: Identifiable {
    let label: String
    let value: String?

    var id: String { label }
}

private struct DetailMetadataGrid: View {
    let rows: [DetailMetadataRow]

    var body: some View {
        VStack(alignment: .leading, spacing: DetailSpacing.xs) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: DetailSpacing.md) {
                    Text(row.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 96, alignment: .leading)

                    Text(displayValue(for: row))
                        .font(.body)
                        .foregroundStyle(row.value == nil ? .tertiary : .primary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DetailSpacing.md)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func displayValue(for row: DetailMetadataRow) -> String {
        guard let value = row.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "Not available"
        }
        return value
    }
}

private extension View {
    @ViewBuilder
    func detailNavigationChrome() -> some View {
        #if os(iOS) || os(tvOS)
        navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

#Preview {
    NavigationStack {
        Text("Movie detail preview requires synced media.")
    }
    .frame(width: 390, height: 844)
}
