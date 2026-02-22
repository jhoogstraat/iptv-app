//
//  EpisodeDetailTile.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 08.09.25.
//

import SwiftUI

struct EpisodeDetailTile: View {
    var body: some View {
        ScopedPlaceholderView(
            title: "Episodes Are Out of Scope",
            message: "Episode-level detail is not included in the current MVP release."
        )
    }
}

#Preview {
    EpisodeDetailTile()
}
