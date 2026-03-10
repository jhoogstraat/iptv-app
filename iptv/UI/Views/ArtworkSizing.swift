//
//  ArtworkSizing.swift
//  iptv
//
//  Created by Codex on 10.03.26.
//

import SwiftUI

extension Image {
    func boundedCoverArtwork() -> some View {
        self
            .resizable()
            .interpolation(.medium)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func boundedFillArtwork() -> some View {
        self
            .resizable()
            .interpolation(.medium)
            .antialiased(true)
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}
