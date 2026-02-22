//
//  VLCKitContentView.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 05.09.25.
//

import SwiftUI

#if canImport(MobileVLCKit)
import MobileVLCKit

#if os(macOS)
struct VLCKitContentView: NSViewRepresentable {
    let player: VLCPlayerReference?

    final class Coordinator: NSObject {
        weak var player: VLCMediaPlayer?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let player = player as? VLCMediaPlayer else { return }
        guard context.coordinator.player !== player else { return }
        context.coordinator.player?.drawable = nil
        player.drawable = nsView
        context.coordinator.player = player
    }
}
#else
struct VLCKitContentView: UIViewRepresentable {
    let player: VLCPlayerReference?

    final class Coordinator: NSObject {
        weak var player: VLCMediaPlayer?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let player = player as? VLCMediaPlayer else { return }
        guard context.coordinator.player !== player else { return }
        context.coordinator.player?.drawable = nil
        player.drawable = uiView
        context.coordinator.player = player
    }
}
#endif

#else

struct VLCKitContentView: View {
    let player: VLCPlayerReference?

    var body: some View {
        _ = player
        return Color.black
    }
}

#endif
