//
//  ContinueWatchingCardView.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import SwiftUI

struct ContinueWatchingCardView: View {
    let item: Media

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: item.cover) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .boundedCoverArtwork()
                    case .failure:
                        Color.gray.opacity(0.25)
                    case .empty:
                        Color.gray.opacity(0.25)
                            .overlay { ProgressView() }
                    @unknown default:
                        Color.gray.opacity(0.25)
                    }
                }

                if let progress = item.activity?.progress {
                    ProgressView(value: progress)
                        .tint(.white)
                        .padding(8)
                }
            }
            .frame(height: 195)
            .background(Color.secondary.opacity(0.12))
            .clipShape(.rect(cornerRadius: 10))

            Text(item.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)

//            if let activity = item.activity?,
//               let remaining = activity.remainingSeconds {
//                Text("\(formattedDuration(remaining)) left")
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
//            }
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let minutes = max(Int(seconds / 60), 1)
        return "\(minutes)m"
    }
}
