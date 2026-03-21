/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model class that defines the properties of a genre.
*/

import Foundation
import SwiftData

@Model class Category: Identifiable {
    var name: String
    
    @Attribute(.unique)
    var remoteId: String
    
    @Relationship(deleteRule: .cascade, inverse: \Media.category)
    var media: [Media]
    
    // For grouping according to some prefix |NL|
    var group: String?
    
    init(remoteId: String, name: String, group: String? = nil, media: [Media] = []) {
        self.remoteId = remoteId
        self.name = name
        self.group = group
        self.media = media
    }
    
    static func countMedia(of remoteId: String, on context: ModelContext) throws -> Int {
        var descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.remoteId == remoteId })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.media.count ?? 0
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class MovieCategory: Category {
    
    @Relationship(deleteRule: .cascade, inverse: \Media.category)
    var movies: [Movie]
    
    init(remoteId: String, name: String, group: String? = nil, movies: [Movie] = []) {
        self.movies = movies
        super.init(remoteId: remoteId, name: name, group: group)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class SeriesCategory: Category {

    @Relationship(deleteRule: .cascade, inverse: \Media.category)
    var series: [Series]
    
    init(remoteId: String, name: String, group: String? = nil, series: [Series] = []) {
        self.series = series
        super.init(remoteId: remoteId, name: name, group: group)
    }
}
