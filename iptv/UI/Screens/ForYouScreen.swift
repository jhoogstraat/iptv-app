//
//  ForYouScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI

struct ForYouScreen: View {
    var body: some View {
        NavigationStack {
            ScopedPlaceholderView(
                title: "For You In Progress",
                message: "The personalized landing screen is being migrated to SQLiteData."
            )
            .navigationTitle("For You")
        }
    }
}

#Preview {
    ForYouScreen()
}
