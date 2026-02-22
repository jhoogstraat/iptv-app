//
//  ViewModifiers.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 05.09.25.
//

import SwiftUI

extension View {
    #if !os(visionOS)
    // Only used in iOS and tvOS for full-window modal presentation.
    func withVideoPlayer() -> some View {
        #if os(macOS)
        self.modifier(OpenVideoPlayerModifier())
        #else
        self.modifier(FullScreenCoverModalModifier())
        #endif
    }
    #endif
}

#if !os(macOS)
private struct FullScreenCoverModalModifier: ViewModifier {
    @Environment(Player.self) private var player
    @State private var isPresentingPlayer = false
    
    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresentingPlayer) {
                PlayerView()
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.reset()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
            // Observe the player's presentation property.
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
    
    func body(content: Content) -> some View {
        content
            .onChange(of: player.presentation, { oldValue, newValue in
                if newValue == .fullWindow {
                    openWindow(id: PlayerView.identifier)
                }
            })
    }
}
#endif
