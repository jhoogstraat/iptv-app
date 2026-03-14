//
//  VLCKitContentView.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 05.09.25.
//

import SwiftUI

#if canImport(VLCKit)
import VLCKit

#if os(macOS)
struct VLCKitContentView: NSViewRepresentable {
    let backend: VLCPlaybackBackend?

    final class Coordinator: NSObject {
        weak var backend: VLCPlaybackBackend?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> VLCVideoView {
        let view = VLCVideoView()
        view.backColor = .black
        return view
    }

    func updateNSView(_ nsView: VLCVideoView, context: Context) {
        guard context.coordinator.backend !== backend else { return }
        context.coordinator.backend?.attachDrawable(nil)
        backend?.attachDrawable(nsView)
        context.coordinator.backend = backend
    }
}
#else
struct VLCKitContentView: UIViewRepresentable {
    let backend: VLCPlaybackBackend?

    final class Coordinator: NSObject {
        weak var backend: VLCPlaybackBackend?
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
        guard context.coordinator.backend !== backend else { return }
        context.coordinator.backend?.attachDrawable(nil)
        backend?.attachDrawable(uiView)
        context.coordinator.backend = backend
    }
}
#endif

#else

struct VLCKitContentView: View {
    let backend: VLCPlaybackBackend?

    var body: some View {
        _ = backend
        return Color.black
    }
}

#endif
