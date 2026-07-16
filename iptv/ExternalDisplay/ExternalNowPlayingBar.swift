import SwiftUI

struct ExternalNowPlayingBar: View {
    @Environment(Player.self) private var player
    @Environment(PlaybackDestinationCoordinator.self) private var destinationCoordinator

    var body: some View {
        if destinationCoordinator.isPlayingOffDevice, let item = player.currentItem {
            HStack(spacing: 12) {
                Button {
                    player.presentation == .fullWindow
                        ? player.dismissController()
                        : reopenController()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Label(destinationCoordinator.selectedDestinationName, systemImage: "airplayvideo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now playing \(item.title) on \(destinationCoordinator.selectedDestinationName)")
                .accessibilityValue(destinationCoordinator.connectionState.accessibilityLabel)

                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                if destinationCoordinator.needsLocalContinuation {
                    Button("Continue Here") {
                        player.continuePlaybackOnDevice()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .accessibilityElement(children: .contain)
        }
    }

    private func reopenController() {
        player.showController()
    }
}

struct WiredDisplayConnectionBanner: View {
    @Environment(PlaybackDestinationCoordinator.self) private var destinationCoordinator

    var body: some View {
        if let destination = destinationCoordinator.pendingWiredDestination {
            HStack(spacing: 12) {
                Label("\(destination.name) connected", systemImage: "display")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Keep on Device") {
                    destinationCoordinator.keepPlaybackOnDevice()
                }
                .buttonStyle(.bordered)
                Button("Play on Display") {
                    destinationCoordinator.playOnPendingWiredDisplay()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Display connected. \(destination.name)")
        }
    }
}
