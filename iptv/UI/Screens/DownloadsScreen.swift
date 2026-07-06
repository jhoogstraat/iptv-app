//
//  DownloadsScreen.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import SwiftUI

struct DownloadsScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Downloads unavailable", systemImage: "arrow.down.circle")
            } description: {
                Text("Offline downloads are intentionally deferred until profiles, a persisted download queue, storage manifests, and local playback source selection are in place.")
            } actions: {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Supported later: direct movie and episode files", systemImage: "film")
                    Label("Not supported: live streams, catch-up, or DRM-protected assets", systemImage: "exclamationmark.triangle")
                    Label("Current playback continues to stream from the active provider", systemImage: "play.rectangle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Downloads")
        }
    }
}

