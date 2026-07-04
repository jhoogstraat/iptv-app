//
//  LibraryScreen.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import SwiftUI

struct FavoritesScreen: View {
    var body: some View {
        NavigationStack {
            ScopedPlaceholderView(
                title: "Favorites In Progress",
                message: "Favorites are being migrated to SQLiteData."
            )
            .navigationTitle("Favorites")
        }
    }
}

#Preview {
    FavoritesScreen()
}
