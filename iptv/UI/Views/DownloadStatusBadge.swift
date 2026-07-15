import SwiftUI
import SQLiteData
import Dependencies

struct DownloadStatusBadge: View {
    let media: Media
    let presentation: DownloadStatusBadgePresentation

    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @Dependency(\.defaultDatabase) private var database
    @FetchAll private var downloads: [DownloadItem]
    @State private var errorMessage: String?

    init(media: Media, presentation: DownloadStatusBadgePresentation = .capsule) {
        self.media = media
        self.presentation = presentation
    }

    private var item: DownloadItem? {
        downloads.first {
            $0.profileID == session.activeProfileID
                && $0.providerID == session.providerID
                && $0.mediaType == media.type
                && $0.sourceID == media.sourceID
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch presentation {
            case .capsule:
                downloadButton
                    .buttonStyle(.bordered)
            case .detailAction(let variant):
                downloadButton
                    .buttonStyle(DetailActionStyle(variant: variant))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let storedError = item?.errorMessage {
                Text(storedError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var downloadButton: some View {
        Button(action: performAction) {
            statusLabel
                .frame(maxWidth: presentation.isDetailAction ? .infinity : nil)
        }
        .disabled(media.type != .movie && media.type != .episode)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch item?.status {
        case .queued, .downloading:
            Label("Pause Download", systemImage: "pause.circle")
        case .paused:
            Label("Resume Download", systemImage: "arrow.down.circle")
        case .completed:
            Label("Remove Download", systemImage: "checkmark.circle.fill")
        case .failed:
            Label("Retry Download", systemImage: "arrow.clockwise.circle")
        case nil:
            Label("Download", systemImage: "arrow.down.circle")
        }
    }

    private func performAction() {
        do {
            if let item {
                switch item.status {
                case .queued, .downloading:
                    DownloadCoordinator.shared.pause(item, database: database)
                case .paused, .failed:
                    DownloadCoordinator.shared.resume(item, database: database)
                case .completed:
                    try DownloadCoordinator.shared.remove(item, database: database)
                }
            } else {
                try player.download(media)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension DownloadStatusBadgePresentation {
    var isDetailAction: Bool {
        if case .detailAction = self { return true }
        return false
    }
}
