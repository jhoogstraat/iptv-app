//
//  ContinueWatchingCardView.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import SwiftUI

enum ForYouWatchProgress {
    static func description(for activity: WatchActivity) -> String {
        let elapsed = formattedDuration(activity.currentTime)
        if let remaining = activity.remainingSeconds {
            return "\(elapsed) watched • \(formattedDuration(remaining)) left"
        }
        return "\(elapsed) watched"
    }

    static func formattedDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0m" }

        let totalMinutes = max(Int(seconds / 60), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

struct ContinueWatchingCardView: View {
    let item: Media
    let activity: WatchActivity?
    let progressDescription: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        item: Media,
        activity: WatchActivity? = nil,
        progressDescription: String? = nil
    ) {
        self.item = item
        self.activity = activity
        self.progressDescription = progressDescription
            ?? activity.map(ForYouWatchProgress.description(for:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: item.backdropURL ?? item.coverURL) { phase in
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

                if let activity,
                   let duration = activity.duration,
                   duration.isFinite,
                   duration > 0 {
                    ProgressView(value: activity.progressFraction)
                        .tint(.white)
                        .padding(10)
                        .accessibilityHidden(true)
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.12))
            .clipShape(.rect(cornerRadius: 10))

            Text(item.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if let progressDescription {
                Text(progressDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(progressDescription ?? "")
        .accessibilityIdentifier(ForYouMediaIdentity.continueWatching(for: item))
    }

    private var artworkPlaceholder: some View {
        Rectangle()
            .fill(.gray.opacity(0.25))
            .overlay {
                Image(systemName: "play.rectangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
    }
}
