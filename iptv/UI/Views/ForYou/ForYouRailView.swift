//
//  ForYouRailView.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import SwiftUI

enum ForYouBadge {
    case new
    case series

    var accessibilityDescription: String {
        switch self {
        case .new: "New"
        case .series: "Series"
        }
    }
}

enum ForYouMediaIdentity {
    static func poster(for media: Media) -> String {
        "forYou.poster.\(media.type.rawValue).\(media.sourceID)"
    }

    static func continueWatching(for media: Media) -> String {
        "forYou.continue.\(media.type.rawValue).\(media.sourceID)"
    }
}

struct ForYouRailView<Destination: View>: View {
    let title: String
    let subtitle: String?
    let items: [Media]
    let badge: (Media) -> ForYouBadge?
    let destination: (Media) -> Destination

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        subtitle: String? = nil,
        items: [Media],
        badge: @escaping (Media) -> ForYouBadge? = { _ in nil },
        @ViewBuilder destination: @escaping (Media) -> Destination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.badge = badge
        self.destination = destination
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: cardSpacing) {
                    ForEach(items) { item in
                        NavigationLink {
                            destination(item)
                        } label: {
                            ForYouPosterCard(item: item, badge: badge(item))
                                .frame(width: cardWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, focusPadding)
                #if os(tvOS)
                .focusSection()
                #endif
            }
            .scrollIndicators(.never)
        }
    }

    private var cardWidth: CGFloat {
        #if os(tvOS)
        260
        #elseif os(macOS)
        dynamicTypeSize.isAccessibilitySize ? 230 : 190
        #else
        if dynamicTypeSize.isAccessibilitySize { return 220 }
        return horizontalSizeClass == .compact ? 160 : 190
        #endif
    }

    private var cardSpacing: CGFloat {
        #if os(tvOS)
        36
        #else
        16
        #endif
    }

    private var focusPadding: CGFloat {
        #if os(tvOS)
        18
        #else
        2
        #endif
    }
}

private struct ForYouPosterCard: View {
    let item: Media
    let badge: ForYouBadge?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: item.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .boundedCoverArtwork()
                    case .empty:
                        artworkPlaceholder
                            .overlay { ProgressView() }
                    case .failure:
                        artworkPlaceholder
                    @unknown default:
                        artworkPlaceholder
                    }
                }
                .accessibilityHidden(true)

                if let badge {
                    badgeView(badge)
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.12))
            .clipShape(.rect(cornerRadius: 10))

            Text(item.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(badge?.accessibilityDescription ?? "")
        .accessibilityIdentifier(ForYouMediaIdentity.poster(for: item))
    }

    private var artworkPlaceholder: some View {
        Rectangle()
            .fill(.gray.opacity(0.25))
            .overlay {
                Image(systemName: item.type == .series ? "rectangle.stack" : "film")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
    }

    @ViewBuilder
    private func badgeView(_ badge: ForYouBadge) -> some View {
        switch badge {
        case .new:
            Text("NEW")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .clipShape(.capsule)
        case .series:
            Text("SERIES")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .clipShape(.capsule)
        }
    }
}
