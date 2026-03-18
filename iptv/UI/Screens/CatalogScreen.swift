//
//  CatalogScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 17.03.26.
//

import SwiftUI
import SwiftData

struct CatalogScreen: View {
    
    @Environment(SessionManager.self) var sessionManager
    
    @Query private var categories: [MovieCategory]
    
    var body: some View {
        List(categories) { category in
            Section(header: Text(category.name)) {
                ForEach(category.movies) { movie in
                    Text(movie.name)
                }
            }
        }
    }
}

#Preview(traits: .previewData, .fixedLayout(width: 1000, height: 500)) {
    CatalogScreen()
}
