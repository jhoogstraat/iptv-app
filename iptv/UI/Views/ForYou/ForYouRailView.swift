//
//  ForYouRailView.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import SwiftUI

struct ForYouRailView<Destination: View>: View {
    let section: ForYouSection
    let destination: (ForYouItem) -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.headline)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(section.items) { item in
                        NavigationLink {
                            destination(item)
                        } label: {
                            ForYouPosterCard(item: item)
                                .frame(width: 170, height: 255)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct ForYouPosterCard: View {
    let item: ForYouItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: item.artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
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

            if let badge = item.badge {
                badgeView(badge)
                    .padding(8)
            }
        }
        .clipShape(.rect(cornerRadius: 10))
    }

    private var fallback: some View {
        Rectangle()
            .fill(.gray.opacity(0.25))
            .overlay {
                Text(item.video.name)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
    }

    @ViewBuilder
    private func badgeView(_ badge: ForYouBadge) -> some View {
        switch badge {
        case .rating(let value):
            Label(value, systemImage: "star.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .clipShape(.capsule)
        case .language(let value):
            Text(value.uppercased())
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .clipShape(.capsule)
        case .isNew:
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
