/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A window that contains the video player for macOS.
*/

import SwiftUI

/// A window that contains the video player for macOS.
#if os(macOS)
struct PlayerWindow: Scene {
    /// An object that controls the video playback behavior.
    var player: Player
    var catalog: Catalog
    var providerStore: ProviderStore
    var favoritesStore: FavoritesStore

    var body: some Scene {
        // The macOS client presents the player view in a separate window.
        WindowGroup(id: PlayerView.identifier) {
            PlayerView()
                .environment(player)
                .environment(catalog)
                .environment(providerStore)
                .environment(favoritesStore)
                .onAppear {
                    player.play()
                }
                .onDisappear {
                    player.reset()
                }
                // Set the minimum window size.
                .frame(minWidth: 960,
                       maxWidth: .infinity,
                       minHeight: 512,
                       maxHeight: .infinity)
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                // Allow the content to extend up the the window's edge,
                // past the safe area.
                .ignoresSafeArea(edges: .top)
        }
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
        .windowIdealPlacement { proxy, context in
            let displayBounds = context.defaultDisplay.visibleRect
            let idealSize = proxy.sizeThatFits(.unspecified)

            // Calculate the content's aspect ratio.
            let aspectRatio = aspectRatio(of: idealSize)
            // Determine the change between the display's size and the content's size.
            let deltas = deltas(of: displayBounds.size, idealSize)

            // Calculate the window's zoomed size while maintaining the aspect ratio
            // of the content.
            let size = calculateZoomedSize(
                of: idealSize,
                inBounds: displayBounds,
                withAspectRatio: aspectRatio,
                andDeltas: deltas
            )

            // Position the window in the center of the display and return the
            // corresponding window placement.
            let position = position(of: size, centeredIn: displayBounds)
            return WindowPlacement(position, size: size)
        }
        .commands {
            CommandMenu("Player") {
                Button(player.isPlaying ? "Pause" : "Play") {
                    player.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(player.currentItem == nil)

                Button("Seek Backward 10s") {
                    player.seek(to: max(player.currentTime - 10, 0))
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(player.currentItem == nil)

                Button("Seek Forward 10s") {
                    let limit = player.duration ?? (player.currentTime + 10)
                    player.seek(to: min(player.currentTime + 10, limit))
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(player.currentItem == nil)

                Divider()

                Menu("Audio Tracks") {
                    if player.capabilities.supportsAudioTracks {
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
                        Text(player.unavailableFeatureMessages.first(where: { $0.hasPrefix("Audio:") }) ?? "Unsupported")
                    }
                }
                .disabled(player.currentItem == nil)

                Menu("Subtitles") {
                    if player.capabilities.supportsSubtitles {
                        Button(menuLabel("Off", selected: player.selectedSubtitleTrackID == MediaTrack.subtitleOffID)) {
                            player.selectSubtitleTrack(id: MediaTrack.subtitleOffID)
                        }
                        ForEach(player.subtitleTracks) { track in
                            Button(menuLabel(track.label, selected: track.id == player.selectedSubtitleTrackID)) {
                                player.selectSubtitleTrack(id: track.id)
                            }
                        }
                    } else {
                        Text(player.unavailableFeatureMessages.first(where: { $0.hasPrefix("Subtitles:") }) ?? "Unsupported")
                    }
                }
                .disabled(player.currentItem == nil)

                Menu("Episodes") {
                    if player.episodeOptions.count > 1 {
                        ForEach(player.episodeOptions, id: \.id) { episode in
                            Button(menuLabel(episode.name, selected: episode.id == player.currentItem?.id)) {
                                player.quickSwitchEpisode(id: episode.id)
                            }
                        }
                    } else {
                        Text("None")
                    }
                }
                .disabled(player.currentItem == nil)

                Menu("More") {
                    if player.capabilities.supportsOutputRouteSelection, !player.outputRoutes.isEmpty {
                        Menu("Output Device") {
                            ForEach(player.outputRoutes) { route in
                                Button(menuLabel(route.name, selected: route.id == player.selectedOutputRouteID)) {
                                    player.selectOutputRoute(id: route.id)
                                }
                            }
                        }
                    }

                    Menu("Playback Speed") {
                        Button("0.5x") { player.setPlaybackSpeed(0.5) }
                        Button("0.75x") { player.setPlaybackSpeed(0.75) }
                        Button("1.0x") { player.setPlaybackSpeed(1.0) }
                        Button("1.25x") { player.setPlaybackSpeed(1.25) }
                        Button("1.5x") { player.setPlaybackSpeed(1.5) }
                        Button("2.0x") { player.setPlaybackSpeed(2.0) }
                    }

                    Menu("Aspect Ratio") {
                        ForEach(player.supportedAspectRatioModes) { mode in
                            Button(mode.label) {
                                player.setAspectRatio(mode)
                            }
                        }
                    }

                    Menu("Sleep Timer") {
                        ForEach(SleepTimerOption.allCases) { option in
                            Button(option.label) {
                                player.setSleepTimer(option)
                            }
                        }
                    }

                    if player.capabilities.supportsAudioDelay {
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
                        Button("Mute") {
                            player.setVolume(0)
                        }
                        Button("50%") {
                            player.setVolume(0.5)
                        }
                        Button("100%") {
                            player.setVolume(1)
                        }
                    }
                }
                .disabled(player.currentItem == nil)
            }
        }
    }
}

extension PlayerWindow {
    private func menuLabel(_ title: String, selected: Bool) -> String {
        selected ? "✓ \(title)" : title
    }

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
