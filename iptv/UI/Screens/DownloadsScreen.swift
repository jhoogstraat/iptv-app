//
//  DownloadsScreen.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import SwiftUI

struct DownloadsScreen: View {
    @Environment(DownloadCenter.self) private var downloadCenter
    @Environment(Player.self) private var player

    var body: some View {
        NavigationStack {
            Group {
                if downloadCenter.visibleGroups.isEmpty {
                    ContentUnavailableView(
                        "No Downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("Download movies or episodes to watch them offline.")
                    )
                } else {
                    List {
                        if !activeGroups.isEmpty {
                            Section("In Progress") {
                                ForEach(activeGroups) { group in
                                    DownloadGroupRow(group: group)
                                }
                            }
                        }

                        if !pausedGroups.isEmpty {
                            Section("Paused") {
                                ForEach(pausedGroups) { group in
                                    DownloadGroupRow(group: group)
                                }
                            }
                        }

                        if !failedGroups.isEmpty {
                            Section("Needs Attention") {
                                ForEach(failedGroups) { group in
                                    DownloadGroupRow(group: group)
                                }
                            }
                        }

                        if !completedGroups.isEmpty {
                            Section("Downloaded") {
                                ForEach(completedGroups) { group in
                                    DownloadGroupRow(group: group)
                                }
                            }
                        }
                    }
                    #if os(macOS)
                    .listStyle(.inset)
                    #else
                    .listStyle(.insetGrouped)
                    #endif
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                if !downloadCenter.visibleGroups.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Remove All") {
                            Task {
                                await downloadCenter.removeAll()
                            }
                        }
                    }
                }
            }
        }
    }

    private var activeGroups: [DownloadGroupRecord] {
        downloadCenter.visibleGroups.filter {
            $0.status == .queued || $0.status == .preparing || $0.status == .downloading
        }
    }

    private var pausedGroups: [DownloadGroupRecord] {
        downloadCenter.visibleGroups.filter { $0.status == .paused }
    }

    private var failedGroups: [DownloadGroupRecord] {
        downloadCenter.visibleGroups.filter { $0.status == .failedRestartable || $0.status == .failedTerminal }
    }

    private var completedGroups: [DownloadGroupRecord] {
        downloadCenter.visibleGroups.filter { $0.status == .completed }
    }
}

private struct DownloadGroupRow: View {
    let group: DownloadGroupRecord

    @Environment(DownloadCenter.self) private var downloadCenter
    @Environment(Player.self) private var player

    @State private var destinationVideo: Video?
    @State private var playError: String?

    var body: some View {
        NavigationLink {
            DownloadGroupDestination(group: group)
        } label: {
            HStack(spacing: 12) {
                artwork

                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if group.status != .completed {
                        ProgressView(value: group.progressFraction)
                    }

                    if let playError {
                        Text(playError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Spacer(minLength: 8)

                controls
            }
            .padding(.vertical, 4)
        }
        .task(id: group.id) {
            destinationVideo = await downloadCenter.displayVideo(for: group)
        }
    }

    private var artwork: some View {
        AsyncImage(url: URL(string: group.coverImageURL ?? "")) { phase in
            switch phase {
            case .success(let image):
                image.boundedCoverArtwork()
            case .empty:
                ZStack {
                    Color.secondary.opacity(0.12)
                    ProgressView()
                }
            default:
                Color.secondary.opacity(0.12)
            }
        }
        .frame(width: 60, height: 90)
        .clipShape(.rect(cornerRadius: 8))
    }

    private var controls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if group.status == .completed {
                Button("Play") {
                    Task {
                        await play()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            switch group.status {
            case .queued, .preparing, .downloading:
                Button("Pause") {
                    Task { await downloadCenter.pause(groupOrAssetID: group.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .paused:
                Button("Resume") {
                    Task { await downloadCenter.resume(groupOrAssetID: group.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .failedRestartable, .failedTerminal:
                Button("Retry") {
                    Task { await downloadCenter.retry(groupOrAssetID: group.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .completed, .removing:
                EmptyView()
            }

            Button(group.status == .completed ? "Remove" : "Cancel") {
                Task { await downloadCenter.remove(groupOrAssetID: group.id) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption.weight(.semibold))
        }
    }

    private var statusText: String {
        switch group.status {
        case .queued:
            return "Queued"
        case .preparing:
            return "Preparing download"
        case .downloading:
            return "\(Int(group.progressFraction * 100))% downloaded"
        case .paused:
            return "Paused"
        case .failedRestartable:
            return "Failed. Ready to retry"
        case .failedTerminal:
            return "Failed"
        case .completed:
            return group.kind == .movie ? "Ready offline" : "\(group.completedAssetCount) episodes ready offline"
        case .removing:
            return "Removing"
        }
    }

    private func play() async {
        let video: Video
        if let destinationVideo {
            video = destinationVideo
        } else {
            video = await downloadCenter.displayVideo(for: group)
        }
        guard let source = await downloadCenter.playbackSourceForGroup(group) else {
            playError = "Downloaded file is unavailable."
            return
        }
        playError = nil
        player.load(video, source, presentation: .fullWindow)
    }
}

private struct DownloadGroupDestination: View {
    let group: DownloadGroupRecord

    @Environment(DownloadCenter.self) private var downloadCenter
    @State private var video: Video?

    var body: some View {
        Group {
            if let video {
                switch video.xtreamContentType {
                case .vod:
                    MovieDetailScreen(video: video)
                case .series:
                    EpisodeDetailTile(video: video)
                case .live:
                    ScopedPlaceholderView(
                        title: "Unsupported Download",
                        message: "Live content is not available for offline playback."
                    )
                }
            } else {
                ProgressView()
            }
        }
        .task(id: group.id) {
            video = await downloadCenter.displayVideo(for: group)
        }
    }
}
