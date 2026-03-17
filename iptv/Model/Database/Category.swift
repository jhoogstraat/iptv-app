/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model class that defines the properties of a genre.
*/

import Foundation
import SwiftData

@Model class Category: Identifiable {
    var name: String
    
    init(name: String) {
        self.name = name
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Movie: Category {
    
    @Relationship(inverse: \MovieMedia.movie)
    var media: MovieMedia
    
    init(name: String, media: MovieMedia) {
        self.media = media
        super.init(name: name)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Series: Category {
    
    @Relationship(inverse: \EpisodeMedia.series)
    var episodes: [EpisodeMedia]
    
    var seasons: Int
    
    init(name: String, episodes: [EpisodeMedia] = [], seasons: Int) {
        self.episodes = episodes
        self.seasons = seasons
        super.init(name: name)
    }
}
