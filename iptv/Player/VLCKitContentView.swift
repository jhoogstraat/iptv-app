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
        let ownerID = UUID()
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
        guard context.coordinator.backend !== backend else { return }
        context.coordinator.backend?.unmountDrawable(ownerID: context.coordinator.ownerID)
        backend?.mountDrawable(in: nsView, ownerID: context.coordinator.ownerID)
        context.coordinator.backend = backend
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.backend?.unmountDrawable(ownerID: coordinator.ownerID)
        coordinator.backend = nil
    }
}
#else
struct VLCKitContentView: UIViewRepresentable {
    let backend: VLCPlaybackBackend?

    final class Coordinator: NSObject {
        weak var backend: VLCPlaybackBackend?
        let ownerID = UUID()
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
        context.coordinator.backend?.unmountDrawable(ownerID: context.coordinator.ownerID)
        backend?.mountDrawable(in: uiView, ownerID: context.coordinator.ownerID)
        context.coordinator.backend = backend
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.backend?.unmountDrawable(ownerID: coordinator.ownerID)
        coordinator.backend = nil
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
