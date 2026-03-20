//
//  Media.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import Foundation
import SwiftData

@Model class MediaInfo: Identifiable {
    var media: Media
    
    var plot: String?
    var runtime: Duration?
    var genre: [String]
    var language: String?
    var backdropURLs: [URL]
    var duration: Duration?
    var coverImageURL: URL?
    var heroImageURL: URL?
    var releaseDate: Date?
    var ageRating: String?
    var country: String?
    var director: [String]
    var cast: [String]
    var actors: [String]
    var mpaaRating: String?

    var episodeRuntime: Int?
    
    init(media: Media, plot: String? = nil, runtime: Duration? = nil, genre: [String], language: String? = nil, backdropURLs: [URL], duration: Duration? = nil, coverImageURL: URL? = nil, heroImageURL: URL? = nil, releaseDate: Date? = nil, ageRating: String? = nil, country: String? = nil, director: [String], cast: [String], actors: [String], mpaaRating: String? = nil, episodeRuntime: Int? = nil) {
        self.media = media
        self.plot = plot
        self.runtime = runtime
        self.genre = genre
        self.language = language
        self.backdropURLs = backdropURLs
        self.duration = duration
        self.coverImageURL = coverImageURL
        self.heroImageURL = heroImageURL
        self.releaseDate = releaseDate
        self.ageRating = ageRating
        self.country = country
        self.director = director
        self.cast = cast
        self.actors = actors
        self.mpaaRating = mpaaRating
        self.episodeRuntime = episodeRuntime
    }

}

@Model class Media: Identifiable {
    var name: String
    var sourceId: Int
    var tmdbId: String?
    var rating: Double?
    var youtubeTrailer: String?
    var coverImageURL: URL?
    
    @Relationship(deleteRule: .cascade, inverse: \MediaInfo.media)
    var info: MediaInfo?
    
    @Relationship(deleteRule: .cascade, inverse: \WatchActivity.media)
    var activity: WatchActivity?
    
    var category: Category
    var isFavorite: Bool = false
    var added: Date
    
    init(name: String, sourceId: Int, tmdbId: String? = nil, rating: Double? = nil, youtubeTrailer: String? = nil, coverImageURL: URL? = nil, info: MediaInfo? = nil, activity: WatchActivity? = nil, category: Category, isFavorite: Bool, added: Date) {
        self.name = name
        self.sourceId = sourceId
        self.tmdbId = tmdbId
        self.rating = rating
        self.youtubeTrailer = youtubeTrailer
        self.coverImageURL = coverImageURL
        self.info = info
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
    
    init(source: MediaSource!, download: Download? = nil) {
        self.source = source
        self.download = download
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Movie: PlayableMedia {
    init(source: MediaSource, download: Download? = nil) {
        super.init(source: source, download: download)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Series: Media {
    @Relationship(deleteRule: .cascade, inverse: \Season.series)
    var seasons: [Season] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Episode.series)
    var episodes: [Episode] = []
     
    init(seasons: [Season], episodes: [Episode]) {
        self.seasons = seasons
        self.episodes = episodes
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Season: Media {
    var seasonNumber: Int
    
    var series: Series
    
    @Relationship(inverse: \Episode.season)
    var episodes: [Episode] = []
    
    init(seasonNumber: Int, series: Series, episodes: [Episode]) {
        self.seasonNumber = seasonNumber
        self.series = series
        self.episodes = episodes
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Episode: PlayableMedia {
    var episodeNumber: Int
    
    var series: Series
    
    var season: Season
    
    init(episodeNumber: Int, series: Series, season: Season) {
        self.episodeNumber = episodeNumber
        self.series = series
        self.season = season
    }
}
