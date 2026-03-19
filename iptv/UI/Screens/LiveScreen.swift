//
//  LiveScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import SwiftUI

struct LiveScreen: View {
    @Environment(ActiveSession.self) private var session
    
    @State private var selectedCategoryID: String?
    @State private var queryText = ""
    @State private var isPresentingSettings = false
    
    init() { }
    
    var body: some View {
        NavigationStack {
            Text("Not yet implemented")
        }
    }
}
