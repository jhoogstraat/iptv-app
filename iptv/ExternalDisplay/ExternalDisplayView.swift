import SwiftUI

struct ExternalDisplayView: View {
    @Environment(Player.self) private var player
    @Environment(PlaybackDestinationCoordinator.self) private var destinationCoordinator
    let sceneID: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if player.currentItem == nil {
                    ExternalDisplayReadyView(message: "Ready to Play")
                } else if destinationCoordinator.rendererIsOwned(by: .externalScene(sceneID)) {
                    PlayerRendererContainer(host: .externalScene(sceneID))
                        .frame(width: proxy.size.width, height: proxy.size.height)

                    if player.isBuffering || player.playbackState == .loading {
                        externalStatus("Loading…", systemImage: "arrow.triangle.2.circlepath")
                    } else if let error = player.errorMessage {
                        externalStatus(sanitized(error), systemImage: "exclamationmark.triangle")
                    }
                } else {
                    ExternalDisplayReadyView(message: "Ready to Play")
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .background(Color.black)
    }

    private func externalStatus(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(24)
            .background(.black.opacity(0.7))
            .clipShape(.rect(cornerRadius: 16))
    }

    private func sanitized(_ message: String) -> String {
        // Backend errors are reduced to a display-safe category. Resolved URLs
        // and provider credentials never cross into the external scene UI.
        _ = message
        return "Playback unavailable"
    }
}

struct ExternalDisplayReadyView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.tv")
                .font(.system(size: 54, weight: .light))
            Text("iptv")
                .font(.largeTitle.bold())
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
