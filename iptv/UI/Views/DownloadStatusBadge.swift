//
//  DownloadStatusBadge.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import SwiftUI

struct DownloadStatusBadge: View {
    var body: some View {
        Label("Offline unavailable", systemImage: "arrow.down.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Offline downloads are unavailable")
            .accessibilityHint("Downloads are deferred until profile-scoped queue and local playback support is implemented.")
    }
}
