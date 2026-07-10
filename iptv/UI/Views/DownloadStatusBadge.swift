//
//  DownloadStatusBadge.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import SwiftUI

struct DownloadStatusBadge: View {
    let presentation: DownloadStatusBadgePresentation

    init(presentation: DownloadStatusBadgePresentation = .capsule) {
        self.presentation = presentation
    }

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .capsule:
            statusLabel
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.secondary.opacity(0.12), in: Capsule(style: .continuous))
        case .detailAction(let variant):
            DetailActionSurface(
                label: statusLabel,
                variant: variant,
                isPressed: false,
                isEnabled: true,
                isFocused: false
            )
        }
    }

    private var statusLabel: some View {
        Label("Download unavailable", systemImage: "arrow.down.circle")
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Downloads unavailable")
            .accessibilityHint("Offline playback is not available.")
    }
}
