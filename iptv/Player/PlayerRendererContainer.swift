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
        .id(player.rendererRevision)
        .background(Color.black)
    }
}
