//
//  PlayerRendererContainer.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import SwiftUI

struct PlayerRendererContainer: View {
    @Environment(Player.self) private var player
    @Environment(PlaybackDestinationCoordinator.self) private var destinationCoordinator
    let host: PlayerRendererHost

    init(host: PlayerRendererHost = .device) {
        self.host = host
    }

    var body: some View {
        Group {
            if destinationCoordinator.rendererIsOwned(by: host) {
                renderer
                    .id(player.rendererRevision)
            } else {
                Color.black
            }
        }
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
