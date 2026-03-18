//
//  Provider.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import Foundation
import SwiftData

@Model class Provider: Identifiable {
    
    @Attribute(.unique)
    var id: UUID = UUID()
    
    @Attribute(.unique)
    var name: String
    
    var isValid: Bool { !name.isEmpty }
    var type: String { "Generic Provider" }
    
    init(name: String) {
        self.name = name
    }
    
    static func with(id: UUID, in context: ModelContext) -> Provider? {
        var descriptor = FetchDescriptor<Provider>(predicate: #Predicate { $0.id == id } )
        descriptor.fetchLimit = 1
        
        return try? context.fetch(descriptor).first
    }
    
    static func with(name: String, in context: ModelContext) -> Provider? {
        var descriptor = FetchDescriptor<Provider>(predicate: #Predicate { $0.name == name } )
        descriptor.fetchLimit = 1
        
        return try? context.fetch(descriptor).first
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class XtreamProvider: Provider {
    var endpoint: URL
    var username: String
    var password: String

    var movies: [Movie]
    var series: [Series]
    
    override var isValid: Bool {
        super.isValid && !username.isEmpty && !password.isEmpty
    }
    
    override var type: String { "Xtream API" }
    
    init(name: String, endpoint: URL, username: String, password: String, movies: [Movie] = [], series: [Series] = []) {
        self.endpoint = endpoint
        self.username = username
        self.password = password
        self.movies = movies
        self.series = series
        super.init(name: name)
    }
}
