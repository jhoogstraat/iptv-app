//
//  LiveScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import SwiftUI

struct LiveScreen: View {
    let contentType: XtreamContentType
    
    @Environment(SessionManager.self) private var sessionManager
    
    @State private var selectedCategoryID: String?
    @State private var queryText = ""
    @State private var isPresentingSettings = false
    
    init(contentType: XtreamContentType = .vod) {
        self.contentType = contentType
    }
    
    var body: some View {
        NavigationStack {
            Text("Not yet implemented")
        }
    }
}
