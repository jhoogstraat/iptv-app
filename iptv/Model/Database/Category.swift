/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model class that defines the properties of a genre.
*/

import Foundation
import SwiftData

/// A model class that defines the properties of a category.
@Model
final class Category: Identifiable {
    @Relationship
    var videos: [Video]
    
    var id: String
    var name: String
    
    init(
        id: String,
        name: String,
        videos: [Video] = []
    ) {
        self.videos = videos
        self.id = id
        self.name = name
    }
}
