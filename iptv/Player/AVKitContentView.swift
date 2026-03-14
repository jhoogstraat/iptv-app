/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that provides an AVKit playback surface.
*/

import AVKit
import SwiftUI

#if os(macOS)
struct AVKitContentView: NSViewRepresentable {
    let player: AVPlayer?
    let mode: PlayerAspectRatioMode

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.player = player
        view.videoGravity = videoGravity(for: mode)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.videoGravity = videoGravity(for: mode)
    }
}
#else
struct AVKitContentView: UIViewControllerRepresentable {
    let player: AVPlayer?
    let mode: PlayerAspectRatioMode

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.player = player
        controller.videoGravity = videoGravity(for: mode)
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        uiViewController.videoGravity = videoGravity(for: mode)
    }
}
#endif

private func videoGravity(for mode: PlayerAspectRatioMode) -> AVLayerVideoGravity {
    switch mode {
    case .fill:
        .resizeAspectFill
    case .fit, .sixteenByNine, .fourByThree, .original:
        .resizeAspect
    }
}
