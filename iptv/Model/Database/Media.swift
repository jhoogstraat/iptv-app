//
//  Media.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import Foundation
import SwiftData

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
    
    var sourceId: Int
    var tmdbId: Int?
    var coverImageURL: URL?
    var heroImageURL: URL?
    
    @Relationship(deleteRule: .cascade, inverse: \WatchActivity.media)
    var activity: WatchActivity?
    
    var category: Category
    var isFavorite: Bool = false
    var added: Date
    
    init(name: String, plot: String? = nil, runtime: Duration? = nil, releaseDate: Date? = nil, ageRating: String? = nil, country: String? = nil, director: String? = nil, cast: String? = nil, rating: Double? = nil, genre: String? = nil, language: String? = nil, sourceId: Int, tmdbId: Int? = nil, coverImageURL: URL? = nil, heroImageURL: URL? = nil, activity: WatchActivity? = nil, category: Category, isFavorite: Bool = false, added: Date = .now) {
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
@Model class PlayableMedia: Media {
    @Relationship(deleteRule: .cascade, inverse: \MediaSource.media)
    var source: MediaSource!
    
    @Relationship(inverse: \Download.media)
    var download: Download?
    
    init(name: String, plot: String? = nil, runtime: Duration? = nil, releaseDate: Date? = nil, ageRating: String? = nil, country: String? = nil, director: String? = nil, cast: String? = nil, rating: Double? = nil, genre: String? = nil, language: String? = nil, sourceId: Int, tmdbId: Int? = nil, coverImageURL: URL? = nil, heroImageURL: URL? = nil, activity: WatchActivity? = nil, category: Category, isFavorite: Bool = false, added: Date = .now, source: MediaSource, download: Download? = nil) {
        self.source = source
        self.download = download
        super.init(name: name, plot: plot, runtime: runtime, releaseDate: releaseDate, ageRating: ageRating, country: country, director: director, cast: cast, rating: rating, genre: genre, language: language, sourceId: sourceId, tmdbId: tmdbId, coverImageURL: coverImageURL, heroImageURL: heroImageURL, activity: activity, category: category, isFavorite: isFavorite, added: added)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Movie: PlayableMedia {    
    init(name: String, plot: String? = nil, runtime: Duration? = nil, releaseDate: Date? = nil, ageRating: String? = nil, country: String? = nil, director: String? = nil, cast: String? = nil, rating: Double? = nil, genre: String? = nil, language: String? = nil, sourceId: Int, tmdbId: Int? = nil, coverImageURL: URL? = nil, heroImageURL: URL? = nil, activity: WatchActivity? = nil, category: Category, isFavorite: Bool = false, added: Date = .now, source: MediaSource) {
        super.init(name: name, plot: plot, runtime: runtime, releaseDate: releaseDate, ageRating: ageRating, country: country, director: director, cast: cast, rating: rating, genre: genre, language: language, sourceId: sourceId, tmdbId: tmdbId, coverImageURL: coverImageURL, heroImageURL: heroImageURL, activity: activity, category: category, isFavorite: isFavorite, added: added, source: source)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Series: Media {
    @Relationship(deleteRule: .cascade, inverse: \Season.series)
    var seasons: [Season] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Episode.series)
    var episodes: [Episode] = []
    
    init(name: String, plot: String? = nil, country: String? = nil, rating: Double? = nil, genre: String? = nil, language: String? = nil, sourceId: Int, tmdbId: Int? = nil, coverImageURL: URL? = nil, heroImageURL: URL? = nil, category: Category, isFavorite: Bool = false, added: Date = .now) {
        super.init(name: name, plot: plot, country: country, rating: rating, genre: genre, language: language, sourceId: sourceId, tmdbId: tmdbId, coverImageURL: coverImageURL, heroImageURL: heroImageURL, category: category, isFavorite: isFavorite, added: added)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Season: Media {
    var seasonNumber: Int
    var series: Series
    
    @Relationship(inverse: \Episode.season)
    var episodes: [Episode] = []
    
    init(name: String, sourceId: Int, tmdbId: Int? = nil, rating: Double? = nil, coverImageURL: URL? = nil, category: Category, seasonNumber: Int, series: Series, added: Date = .now) {
        self.seasonNumber = seasonNumber
        self.series = series
        super.init(name: name, rating: rating, sourceId: sourceId, tmdbId: tmdbId, coverImageURL: coverImageURL, category: category, added: added)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Episode: PlayableMedia {
    var episodeNumber: Int
    var series: Series
    var season: Season
    
    init(name: String, plot: String? = nil, runtime: Duration? = nil, releaseDate: Date? = nil, rating: Double? = nil, sourceId: Int, tmdbId: Int? = nil, coverImageURL: URL? = nil, category: Category, added: Date = .now, series: Series, season: Season, episodeNumber: Int, source: MediaSource) {
        self.series = series
        self.season = season
        self.episodeNumber = episodeNumber
        super.init(name: name, plot: plot, runtime: runtime, releaseDate: releaseDate, rating: rating, sourceId: sourceId, tmdbId: tmdbId, coverImageURL: coverImageURL, category: category, added: added, source: source)
    }
}
