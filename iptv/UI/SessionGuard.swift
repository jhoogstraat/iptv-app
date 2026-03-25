//
//  SessionGuard.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 25.03.26.
//

import SwiftUI

extension View {
    func requireSessionOrElse<V: View>(@ViewBuilder _ elseBuilder: @escaping () -> V) -> some View {
        modifier(SessionGuard(elseBuilder))
    }
}

struct SessionGuard<V: View>: ViewModifier {
    @Environment(ProviderManager.self) var manager
   
    @ViewBuilder var elseBuilder: () -> V
    
    init(@ViewBuilder _ elseBuilder: @escaping () -> V) {
        self.elseBuilder = elseBuilder
    }
    
    func body(content: Content) -> some View {
        if let session = self.manager.session {
           content
               .environment(session)
       } else {
           elseBuilder()
       }
    }
}
