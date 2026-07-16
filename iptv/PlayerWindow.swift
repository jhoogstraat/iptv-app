/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A window that contains the video player for macOS.
*/

import SwiftUI

/// A window that contains the video player for macOS.
#if os(macOS)
struct PlayerWindow: Scene {
    let bootstrap: RecoverableBootstrap<ApplicationRuntime>

    var body: some Scene {
        WindowGroup(id: PlayerView.identifier) {
            PlayerWindowContent(bootstrap: bootstrap)
        }
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
        .windowIdealPlacement { proxy, context in
            let displayBounds = context.defaultDisplay.visibleRect
            let idealSize = proxy.sizeThatFits(.unspecified)
            let aspectRatio = aspectRatio(of: idealSize)
            let deltas = deltas(of: displayBounds.size, idealSize)
            let size = calculateZoomedSize(
                of: idealSize,
                inBounds: displayBounds,
                withAspectRatio: aspectRatio,
                andDeltas: deltas
            )
            let position = position(of: size, centeredIn: displayBounds)
            return WindowPlacement(position, size: size)
        }
        .commands {
            PlayerCommands(bootstrap: bootstrap)
        }
    }
}

private struct PlayerWindowContent: View {
    let bootstrap: RecoverableBootstrap<ApplicationRuntime>

    @ViewBuilder
    var body: some View {
        if let runtime = bootstrap.value {
            PlayerView()
                .withPlayerPresentationLifecycle()
                .environment(runtime.player)
                .environment(runtime.playbackDestinationCoordinator)
                .environment(runtime.providerManager)
                .frame(
                    minWidth: 960,
                    maxWidth: .infinity,
                    minHeight: 512,
                    maxHeight: .infinity
                )
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .ignoresSafeArea(edges: .top)
        } else {
            EmptyView()
        }
    }
}

private struct PlayerCommands: Commands {
    let bootstrap: RecoverableBootstrap<ApplicationRuntime>

    private var player: Player? {
        bootstrap.value?.player
    }

    var body: some Commands {
        CommandMenu("Player") {
            Button(player?.isPlaybackComplete == true ? "Replay" : (player?.isPlaying == true ? "Pause" : "Play")) {
                player?.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(
                player?.currentItem == nil
                    || player?.isPlaybackComplete == true && player?.currentItem?.type == .live
            )

            Button("Seek Backward 10s") {
                guard let player else { return }
                player.seek(by: -10)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .disabled(player?.currentItem == nil || player?.currentItem?.type == .live)

            Button("Seek Forward 10s") {
                guard let player else { return }
                player.seek(by: 10)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .disabled(player?.currentItem == nil || player?.currentItem?.type == .live)

            Divider()

            Menu("Audio Tracks") {
                if let player, player.capabilities.supportsAudioTracks {
                    if player.audioTracks.isEmpty {
                        Text("No tracks")
                    } else {
                        ForEach(player.audioTracks) { track in
                            Button(menuLabel(track.label, selected: track.id == player.selectedAudioTrackID)) {
                                player.selectAudioTrack(id: track.id)
                            }
                        }
                    }
                } else {
                    Text(player?.unavailableFeatureMessages.first(where: { $0.hasPrefix("Audio:") }) ?? "Unsupported")
                }
            }
            .disabled(player?.currentItem == nil)

            Menu("Subtitles") {
                if let player, player.capabilities.supportsSubtitles {
                    Button(menuLabel("Off", selected: player.selectedSubtitleTrackID == MediaTrack.subtitleOffID)) {
                        player.selectSubtitleTrack(id: MediaTrack.subtitleOffID)
                    }
                    ForEach(player.subtitleTracks) { track in
                        Button(menuLabel(track.label, selected: track.id == player.selectedSubtitleTrackID)) {
                            player.selectSubtitleTrack(id: track.id)
                        }
                    }
                } else {
                    Text(player?.unavailableFeatureMessages.first(where: { $0.hasPrefix("Subtitles:") }) ?? "Unsupported")
                }
            }
            .disabled(player?.currentItem == nil)

            Menu("More") {
                if let player, player.capabilities.supportsOutputRouteSelection, !player.outputRoutes.isEmpty {
                    Menu("Output Device") {
                        ForEach(player.outputRoutes) { route in
                            Button(menuLabel(route.name, selected: route.id == player.selectedOutputRouteID)) {
                                player.selectOutputRoute(id: route.id)
                            }
                        }
                    }
                }

                Menu("Playback Speed") {
                    Button("0.5x") { player?.setPlaybackSpeed(0.5) }
                    Button("0.75x") { player?.setPlaybackSpeed(0.75) }
                    Button("1.0x") { player?.setPlaybackSpeed(1.0) }
                    Button("1.25x") { player?.setPlaybackSpeed(1.25) }
                    Button("1.5x") { player?.setPlaybackSpeed(1.5) }
                    Button("2.0x") { player?.setPlaybackSpeed(2.0) }
                }
                .disabled(player?.currentItem?.type == .live)

                Menu("Aspect Ratio") {
                    ForEach(player?.supportedAspectRatioModes ?? []) { mode in
                        Button(mode.label) {
                            player?.setAspectRatio(mode)
                        }
                    }
                }

                Menu("Sleep Timer") {
                    ForEach(SleepTimerOption.allCases) { option in
                        Button(option.label) {
                            player?.setSleepTimer(option)
                        }
                    }
                }

                if let player, player.capabilities.supportsAudioDelay {
                    Menu("Audio Delay") {
                        Button("Reset to 0 ms") {
                            player.resetAudioDelay()
                        }
                        .disabled(player.audioDelayMilliseconds == 0)

                        Button("-250 ms") {
                            player.setAudioDelay(milliseconds: player.audioDelayMilliseconds - 250)
                        }

                        Button("+250 ms") {
                            player.setAudioDelay(milliseconds: player.audioDelayMilliseconds + 250)
                        }
                    }
                }

                Menu("Volume") {
                    Button("Mute") { player?.setVolume(0) }
                    Button("50%") { player?.setVolume(0.5) }
                    Button("100%") { player?.setVolume(1) }
                }
            }
            .disabled(player?.currentItem == nil)
        }
    }

    private func menuLabel(_ title: String, selected: Bool) -> String {
        selected ? "✓ \(title)" : title
    }
}

extension PlayerWindow {
    /// Calculates the aspect ratio of the specified size.
    func aspectRatio(of size: CGSize) -> CGFloat {
        size.width / size.height
    }
    
    /// Calculates the center point of a size so the player appears in the center of the specified rectangle.
    func deltas(
        of size: CGSize,
        _ otherSize: CGSize
    ) -> (width: CGFloat, height: CGFloat) {
        (size.width / otherSize.width, size.height / otherSize.height)
    }
    
    /// Calculates the center point of a size so the player appears in the center of the specified rectangle.
    func position(
        of size: CGSize,
        centeredIn bounds: CGRect
    ) -> CGPoint {
        let midWidth = size.width / 2
        let midHeight = size.height / 2
        return .init(x: bounds.midX - midWidth, y: bounds.midY - midHeight)
    }
    
    /// Calculates the largest size a window can be in the current display, while maintaining the window's aspect ratio.
    func calculateZoomedSize(
        of currentSize: CGSize,
        inBounds bounds: CGRect,
        withAspectRatio aspectRatio: CGFloat,
        andDeltas deltas: (width: CGFloat, height: CGFloat)
    ) -> CGSize {
        if (aspectRatio > 1 && currentSize.height * deltas.width <= bounds.height)
            || (aspectRatio < 1 && currentSize.width * deltas.height <= bounds.width) {
            return .init(
                width: bounds.width,
                height: currentSize.height * deltas.width
            )
        } else {
            return .init(
                width: currentSize.width * deltas.height,
                height: bounds.height
            )
        }
    }
}
#endif
