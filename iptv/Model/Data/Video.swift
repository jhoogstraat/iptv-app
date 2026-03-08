/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model class that defines the properties of a video.
*/

import Foundation
import SwiftData
import CoreMedia
import SwiftUI

/// A model class that defines the properties of a video.
@Model
final class Video: Identifiable {
   
    var id: Int
    var categories: [Category]
    var name: String
    var containerExtension: String
    var contentType: String
    var coverImageURL: String?
    var tmdbId: String?
    var rating: Double?
    var addedAtRaw: String?
    var startTime: CMTimeValue
    var isHero: Bool
    var isFeatured: Bool
    
    init(
        id: Int,
        name: String,
        containerExtension: String,
        contentType: String,
        categories: [Category] = [],
        coverImageURL: String?,
        startTime: CMTimeValue = 0,
        tmdbId: String?,
        rating: Double?,
        addedAtRaw: String? = nil,
        isHero: Bool = false,
        isFeatured: Bool = false
    ) {
        self.id = id
        self.name = name
        self.contentType = contentType
        self.containerExtension = containerExtension
        self.categories = categories
        self.coverImageURL = coverImageURL
        self.startTime = startTime
        self.tmdbId = tmdbId
        self.rating = rating
        self.addedAtRaw = addedAtRaw
        self.isHero = isHero
        self.isFeatured = isFeatured
    }
}

extension Video {
    var formattedRating: String? {
        if let rating = rating {
            return rating.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
        }
        return nil
    }
    
    var language: String? {
        LanguageTaggedText(name).languageCode
    }

    var xtreamContentType: XtreamContentType {
        switch contentType {
        case XtreamContentType.series.rawValue:
            .series
        case XtreamContentType.live.rawValue:
            .live
        default:
            .vod
        }
    }
}
