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

    var body: some Scene {
        // The macOS client presents the player view in a separate window.
        WindowGroup(id: PlayerView.identifier) {
            PlayerView()
                .environment(player)
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
        .windowResizability(.contentSize)
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
