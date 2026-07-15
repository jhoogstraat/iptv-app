import SwiftUI
import SQLiteData
import Dependencies

struct DownloadsScreen: View {
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @Dependency(\.defaultDatabase) private var database
    @FetchAll private var downloads: [DownloadItem]
    @FetchAll private var media: [Media]
    @State private var errorMessage: String?

    private var visibleDownloads: [DownloadItem] {
        downloads
            .filter { $0.profileID == session.activeProfileID && $0.providerID == session.providerID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleDownloads.isEmpty {
                    ContentUnavailableView {
                        Label("No Downloads", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Download a movie or episode from its detail screen for offline playback.")
                    }
                } else {
                    List(visibleDownloads) { item in
                        downloadRow(item)
                    }
                }
            }
            .navigationTitle("Downloads")
            .alert("Download Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func downloadRow(_ item: DownloadItem) -> some View {
        let playableMedia = item.status == .completed ? mediaItem(for: item) : nil

        return HStack(spacing: 12) {
            downloadContent(for: item, playableMedia: playableMedia)

            Menu {
                actions(for: item, playableMedia: playableMedia)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Actions for \(item.title)")
        }
    }

    @ViewBuilder
    private func downloadContent(for item: DownloadItem, playableMedia: Media?) -> some View {
        if let playableMedia {
            let button = Button {
                player.load(playableMedia, presentation: .fullWindow)
            } label: {
                downloadLabel(for: item)
            }
            .accessibilityLabel("Play \(item.title)")
            .accessibilityHint("Starts offline playback")

            #if os(tvOS)
            button
            #else
            button.buttonStyle(.plain)
            #endif
        } else {
            downloadLabel(for: item)
                .accessibilityElement(children: .combine)
        }
    }

    private func downloadLabel(for item: DownloadItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol(for: item.status))
                .foregroundStyle(item.status == .failed ? .red : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                Text(statusTitle(for: item.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = item.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actions(for item: DownloadItem, playableMedia: Media?) -> some View {
        switch item.status {
        case .queued, .downloading:
            Button("Pause", systemImage: "pause") {
                DownloadCoordinator.shared.pause(item, database: database)
            }
        case .paused, .failed:
            Button("Resume", systemImage: "arrow.down") {
                DownloadCoordinator.shared.resume(item, database: database)
            }
        case .completed:
            if let playableMedia {
                Button("Play Offline", systemImage: "play.fill") {
                    player.load(playableMedia, presentation: .fullWindow)
                }
            }
        }
        Button("Remove", systemImage: "trash", role: .destructive) {
            do {
                try DownloadCoordinator.shared.remove(item, database: database)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func mediaItem(for item: DownloadItem) -> Media? {
        media.first { $0.type == item.mediaType && $0.sourceID == item.sourceID }
    }

    private func statusTitle(for status: DownloadStatus) -> String {
        switch status {
        case .queued: "Queued"
        case .downloading: "Downloading"
        case .paused: "Paused"
        case .completed: "Ready Offline"
        case .failed: "Failed"
        }
    }

    private func statusSymbol(for status: DownloadStatus) -> String {
        switch status {
        case .queued: "clock"
        case .downloading: "arrow.down.circle.fill"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}
