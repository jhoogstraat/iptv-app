//
//  PlayerRendererContainer.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import SwiftUI

struct PlayerRendererContainer: View {
    @Environment(Player.self) private var player

    var body: some View {
        renderer
            .modifier(PlayerAspectRatioModifier(mode: player.aspectRatioMode))
            .id(player.rendererRevision)
            .background(Color.black)
    }

    @ViewBuilder
    private var renderer: some View {
        Group {
            switch player.activeBackendID {
            case .vlc:
                VLCKitContentView(player: player.vlcRenderer)
            case .av:
                AVKitContentView(player: player.avRenderer)
            case .none:
                Color.black
            }
        }
    }
}

private struct PlayerAspectRatioModifier: ViewModifier {
    let mode: PlayerAspectRatioMode

    @ViewBuilder
    func body(content: Content) -> some View {
        switch mode {
        case .fill:
            content
                .aspectRatio(contentMode: .fill)
                .clipped()
        case .sixteenByNine, .fourByThree:
            content
                .aspectRatio(mode.fixedAspectRatio, contentMode: .fit)
        case .fit, .original:
            content
                .aspectRatio(contentMode: .fit)
        }
    }
}
