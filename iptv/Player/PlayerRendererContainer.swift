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
            .id(player.rendererRevision)
            .background(Color.black)
    }

    @ViewBuilder
    private var renderer: some View {
        Group {
            switch player.activeBackendID {
            case .vlc:
                VLCKitContentView(backend: player.vlcBackend)
            case .av:
                AVKitContentView(player: player.avRenderer, mode: player.aspectRatioMode)
            case .none:
                Color.black
            }
        }
    }
}
