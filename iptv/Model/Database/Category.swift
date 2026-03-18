/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model class that defines the properties of a genre.
*/

import Foundation
import SwiftData

@Model class Category: Identifiable {
    var name: String
    
    @Relationship(inverse: \Media.category)
    var media: [Media]
    
    // For grouping according to some prefix |NL|
    var group: String?
    
    init(name: String, group: String? = nil, media: [Media] = []) {
        self.name = name
        self.group = group
        self.media = media
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class MovieCategory: Category {
    
    @Relationship(inverse: \Media.category)
    var movies: [Movie]
    
    init(name: String, group: String? = nil, movies: [Movie] = []) {
        self.movies = movies
        super.init(name: name, group: group)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class SeriesCategory: Category {

    @Relationship(inverse: \Media.category)
    var series: [Series]
    
    init(name: String, group: String? = nil, series: [Series] = []) {
        self.series = series
        super.init(name: name, group: group)
    }
}
