//
//  ForYouRailView.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import SwiftUI

enum ForYouBadge {
    case new, series
}

struct ForYouRailView<Destination: View>: View {
    let title: String
    let subtitle: String?
    let items: [Media]
    let badge: (Media) -> ForYouBadge?
    let destination: (Media) -> Destination

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
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink {
                            destination(item)
                        } label: {
                            ForYouPosterCard(item: item, badge: badge(item))
                                .frame(width: 170, height: 255)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.never)
        }
    }
}

private struct ForYouPosterCard: View {
    let item: Media
    let badge: ForYouBadge?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: item.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .boundedCoverArtwork()
                case .failure:
                    fallback
                case .empty:
                    Rectangle()
                        .fill(.gray.opacity(0.25))
                        .overlay { ProgressView() }
                @unknown default:
                    fallback
                }
            }

            if let badge {
                badgeView(badge)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.12))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var fallback: some View {
        Rectangle()
            .fill(.gray.opacity(0.25))
            .overlay {
                Text(item.title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
    }

    @ViewBuilder
    private func badgeView(_ badge: ForYouBadge) -> some View {
        switch badge {
//        case .rating(let value):
//            Label(value, systemImage: "star.fill")
//                .labelStyle(.titleAndIcon)
//                .font(.caption2.weight(.semibold))
//                .padding(.horizontal, 6)
//                .padding(.vertical, 4)
//                .background(.thinMaterial)
//                .clipShape(.capsule)
//        case .language(let value):
//            Text(value.uppercased())
//                .font(.caption2.weight(.semibold))
//                .padding(.horizontal, 6)
//                .padding(.vertical, 4)
//                .background(.thinMaterial)
//                .clipShape(.capsule)
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
