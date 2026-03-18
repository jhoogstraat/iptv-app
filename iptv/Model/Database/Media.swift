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
    var runtime: Duration?
    var releaseDate: Date?
    var ageRating: String?
    var country: String?
    var director: String?
    var cast: String?
    var rating: Double?
    var genre: String?
    var language: String?
    
    var sourceId: String?
    var tmdbId: String?
    var coverImageURL: URL?
    var heroImageURL: URL?
    

    @Relationship(deleteRule: .cascade, inverse: \WatchActivity.media)
    var activity: WatchActivity?
    
    var category: Category
    
    var isFavorite: Bool = false
    var added: Date
    
    init(name: String, plot: String? = nil, runtime: Duration? = nil, releaseDate: Date? = nil, ageRating: String? = nil, country: String? = nil, director: String? = nil, cast: String? = nil, rating: Double? = nil, genre: String? = nil, language: String? = nil, sourceId: String? = nil, tmdbId: String? = nil, coverImageURL: URL? = nil, heroImageURL: URL? = nil, activity: WatchActivity? = nil, category: Category, isFavorite: Bool = false, added: Date) {
        self.name = name
        self.plot = plot
        self.runtime = runtime
        self.releaseDate = releaseDate
        self.ageRating = ageRating
        self.country = country
        self.director = director
        self.cast = cast
        self.rating = rating
        self.genre = genre
        self.language = language
        self.sourceId = sourceId
        self.tmdbId = tmdbId
        self.coverImageURL = coverImageURL
        self.heroImageURL = heroImageURL
        self.activity = activity
        self.category = category
        self.isFavorite = isFavorite
        self.added = added
    }
    
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Movie: PlayableMedia {
    
    init(name: String, coverImageURL: URL?, tmdbId: String?, rating: Double?, source: MediaSource, category: Category) {
        super.init(name: name, coverImageURL: coverImageURL, tmdbId: tmdbId, rating: rating, source: source, category: category)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Series: Media {
    
    @Relationship(deleteRule: .cascade, inverse: \Season.series)
    var seasons: [Season]
    
    @Relationship(deleteRule: .cascade, inverse: \Episode.series)
    var episodes: [Episode]
    
    init(name: String, coverImageURL: URL?, tmdbId: String?, rating: Double?, category: Category, seasons: [Season], episodes: [Episode]) {
        self.seasons = seasons
        self.episodes = episodes
        super.init(name: name, rating: rating, tmdbId: tmdbId, coverImageURL: coverImageURL, category: category, added: .now)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Season: Media {
    var season: Int
    
    var series: Series
    
    @Relationship(inverse: \Episode.season)
    var episodes: [Episode]
    
    init(name: String, coverImageURL: URL?, tmdbId: String?, rating: Double?, url: String, source: MediaSource, category: Category, series: Series, episodes: [Episode], season: Int, ) {
        self.series = series
        self.episodes = episodes
        self.season = season
        super.init(name: name, rating: rating, tmdbId: tmdbId, coverImageURL: coverImageURL, category: category, added: .now)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Episode: PlayableMedia {
    var episode: Int
    
    var series: Series
    var season: Season
    
    init(name: String, coverImageURL: URL?, tmdbId: String?, rating: Double?, source: MediaSource, category: Category, series: Series, season: Season, episode: Int) {
        self.series = series
        self.season = season
        self.episode = episode
        super.init(name: name, coverImageURL: coverImageURL, tmdbId: tmdbId, rating: rating, source: source, category: category)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model class PlayableMedia: Media {

    @Relationship(deleteRule: .cascade, inverse: \MediaSource.media)
    var source: MediaSource!
    
    @Relationship(inverse: \Download.media)
    var download: Download?
    
    init(name: String, coverImageURL: URL?, tmdbId: String?, rating: Double?, source: MediaSource, category: Category, download: Download? = nil) {
        self.source = source
        self.download = download
        super.init(name: name, rating: rating, tmdbId: tmdbId, coverImageURL: coverImageURL, category: category, added: .now)
    }
}

extension Media {
    var formattedRating: String? {
        if let rating = rating {
            return rating.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
        }
        return nil
    }
}
