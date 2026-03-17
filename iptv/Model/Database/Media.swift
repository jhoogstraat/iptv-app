//
//  Media.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import Foundation
import SwiftData

/// A model class that defines the properties of a video.
@Model class Media: Identifiable {
    
    var name: String
    var plot: String?
    var runtimeMinutes: Int?
    var releaseDate: String?
    var ageRating: String?
    var country: String?
    var director: String?
    var rating: Double?
    
    var url: String
    var coverImageURL: String?
    var streamBitrate: Int?
    var audioDescription: String?
    var videoResolution: String?
    var videoFrameRate: Double?
    
    var next: Media?
    var previous: Media?
    var tmdbId: String?
    
    var favorite: Bool = false
    var added: Date
    var lastAccess: Date?
    
    init(name: String, plot: String? = nil, runtimeMinutes: Int? = nil, releaseDate: String? = nil, ageRating: String? = nil, country: String? = nil, director: String? = nil, rating: Double? = nil, url: String, coverImageURL: String? = nil, streamBitrate: Int? = nil, audioDescription: String? = nil, videoResolution: String? = nil, videoFrameRate: Double? = nil, next: Media? = nil, previous: Media? = nil, tmdbId: String? = nil, favorite: Bool, added: Date, lastAccess: Date? = nil) {
        self.name = name
        self.plot = plot
        self.runtimeMinutes = runtimeMinutes
        self.releaseDate = releaseDate
        self.ageRating = ageRating
        self.country = country
        self.director = director
        self.rating = rating
        self.url = url
        self.coverImageURL = coverImageURL
        self.streamBitrate = streamBitrate
        self.audioDescription = audioDescription
        self.videoResolution = videoResolution
        self.videoFrameRate = videoFrameRate
        self.next = next
        self.previous = previous
        self.tmdbId = tmdbId
        self.favorite = favorite
        self.added = added
        self.lastAccess = lastAccess
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class MovieMedia: Media {
    
    @Relationship
    var movie: Category
    
    init(name: String, coverImageURL: String?, tmdbId: String?, rating: Double?, url: String, movie: Movie, previous: Media? = nil, next: Media? = nil) {
        self.movie = movie
        super.init(name: name, url: url, next: next, previous: previous, favorite: false, added: .now)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class EpisodeMedia: Media {
    
    @Relationship
    var series: Category
    
    var season: Int
    
    init(name: String, coverImageURL: String?, tmdbId: String?, rating: Double?, url: String, series: Series, season: Int, previous: Media? = nil, next: Media? = nil) {
        self.series = series
        self.season = season
        super.init(name: name, url: url, next: next, previous: previous, favorite: false, added: .now)
    }
}

extension MovieMedia {
    var formattedRating: String? {
        if let rating = rating {
            return rating.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
        }
        return nil
    }
    
    var language: String? {
        LanguageTaggedText(name).languageCode
    }
}
