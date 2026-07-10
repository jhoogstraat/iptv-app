//
//  ViewModifiers.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 05.09.25.
//

import SwiftUI

extension View {
    /// Presents the shared player whenever the player model requests full-window playback.
    func withVideoPlayer() -> some View {
        #if os(macOS)
        modifier(OpenVideoPlayerModifier())
        #else
        modifier(FullScreenCoverModalModifier())
        #endif
    }

    /// Owns playback cleanup for one concrete player presentation.
    func withPlayerPresentationLifecycle() -> some View {
        modifier(PlayerPresentationLifecycleModifier())
    }
}

enum PlayerWindowPresentationAction: Equatable {
    case none
    case open
    case dismiss

    static func action(from oldValue: Presentation, to newValue: Presentation) -> Self {
        switch (oldValue, newValue) {
        case (.inline, .fullWindow):
            return .open
        case (.fullWindow, .inline):
            return .dismiss
        default:
            return .none
        }
    }
}

struct PlayerPresentationLifecycle: Equatable {
    private(set) var didRequestReset = false

    mutating func consumeResetOnDisappear(hasLoadedItem: Bool) -> Bool {
        guard hasLoadedItem, !didRequestReset else { return false }
        didRequestReset = true
        return true
    }
}

private struct PlayerPresentationLifecycleModifier: ViewModifier {
    @Environment(Player.self) private var player
    @State private var lifecycle = PlayerPresentationLifecycle()

    func body(content: Content) -> some View {
        content
            .onDisappear {
                if lifecycle.consumeResetOnDisappear(hasLoadedItem: player.currentItem != nil) {
                    player.reset()
                }
            }
    }
}

#if !os(macOS)
private struct FullScreenCoverModalModifier: ViewModifier {
    @Environment(Player.self) private var player
    @State private var isPresentingPlayer = false
    
    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresentingPlayer) {
                PlayerView()
                    .withPlayerPresentationLifecycle()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
            .onAppear {
                isPresentingPlayer = player.presentation == .fullWindow
            }
            .onChange(of: player.presentation) { _, newPresentation in
                isPresentingPlayer = newPresentation == .fullWindow
            }
    }
}
#endif

#if os(macOS)
private struct OpenVideoPlayerModifier: ViewModifier {
    @Environment(Player.self) private var player
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    func body(content: Content) -> some View {
        content
            .onAppear {
                if player.presentation == .fullWindow {
                    openWindow(id: PlayerView.identifier)
                }
            }
            .onChange(of: player.presentation) { oldValue, newValue in
                switch PlayerWindowPresentationAction.action(from: oldValue, to: newValue) {
                case .open:
                    openWindow(id: PlayerView.identifier)
                case .dismiss:
                    dismissWindow(id: PlayerView.identifier)
                case .none:
                    break
                }
            }
    }
}
#endif
