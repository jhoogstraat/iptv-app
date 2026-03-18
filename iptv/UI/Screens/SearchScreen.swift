//
//  SearchScreen.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import SwiftUI

struct SearchScreen: View {
    
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Search not yet implemented", systemImage: "tray.fill")
        }
    }
}

#Preview(traits: .previewData) {
    SearchScreen()
}
