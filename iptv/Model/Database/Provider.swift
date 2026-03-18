//
//  Provider.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import Foundation
import SwiftData

@Model class Provider: Identifiable {
    var name: String
    
    init(name: String) {
        self.name = name
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class XtreamProvider: Provider {
    var endpoint: URL
    var username: String
    var password: String

    var movies: [Movie]
    var series: [Series]
    
    var isValid: Bool {
         !username.isEmpty && !password.isEmpty
    }
    
    init(name: String, endpoint: URL, username: String, password: String, movies: [Movie] = [], series: [Series] = []) {
        self.endpoint = endpoint
        self.username = username
        self.password = password
        self.movies = movies
        self.series = series
        super.init(name: name)
    }
}
