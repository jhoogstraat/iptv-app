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
    var cover: URL?
    var heroImageURL: URL?
    var releaseDate: Date?
    var ageRating: String?
    var country: String?
    var director: [String]
    var cast: [String]
    var actors: [String]
    var mpaaRating: String?

    var episodeRuntime: Int?
    
    init(media: Media, plot: String? = nil, runtime: Duration? = nil, genre: [String], language: String? = nil, backdropURLs: [URL], duration: Duration? = nil, cover: URL? = nil, heroImageURL: URL? = nil, releaseDate: Date? = nil, ageRating: String? = nil, country: String? = nil, director: [String], cast: [String], actors: [String], mpaaRating: String? = nil, episodeRuntime: Int? = nil) {
        self.media = media
        self.plot = plot
        self.runtime = runtime
        self.genre = genre
        self.language = language
        self.backdropURLs = backdropURLs
        self.duration = duration
        self.cover = cover
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
    var trailer: String?
    var cover: URL?
    var added: Date
    
    var isFavorite: Bool = false
    var category: Category
    
    @Relationship(deleteRule: .cascade, inverse: \MediaInfo.media)
    var info: MediaInfo?
    
    @Relationship(deleteRule: .cascade, inverse: \WatchActivity.media)
    var activity: WatchActivity?
    
    init(name: String, sourceId: Int, tmdbId: String? = nil, rating: Double? = nil, trailer: String? = nil, cover: URL? = nil, added: Date, isFavorite: Bool = false, category: Category, info: MediaInfo? = nil, activity: WatchActivity? = nil) {
        self.name = name
        self.sourceId = sourceId
        self.tmdbId = tmdbId
        self.rating = rating
        self.trailer = trailer
        self.cover = cover
        self.added = added
        self.isFavorite = isFavorite
        self.category = category
        self.info = info
        self.activity = activity
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model class PlayableMedia: Media {
    @Relationship(deleteRule: .cascade, inverse: \MediaSource.media)
    var source: MediaSource!
    
    @Relationship(inverse: \Download.media)
    var download: Download?
    
    init(name: String, sourceId: Int, tmdbId: String? = nil, rating: Double? = nil, trailer: String? = nil, cover: URL? = nil, added: Date, isFavorite: Bool = false, category: Category, info: MediaInfo? = nil, activity: WatchActivity? = nil, source: MediaSource!, download: Download? = nil) {
        self.source = source
        self.download = download
        super.init(name: name, sourceId: sourceId, added: added, isFavorite: isFavorite, category: category)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Movie: PlayableMedia {
    override init(name: String, sourceId: Int, tmdbId: String? = nil, rating: Double? = nil, trailer: String? = nil, cover: URL? = nil, added: Date, isFavorite: Bool = false, category: Category, info: MediaInfo? = nil, activity: WatchActivity? = nil, source: MediaSource!, download: Download? = nil) {
        super.init(name: name, sourceId: sourceId, added: added, isFavorite: isFavorite, category: category, source: source, download: download)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Series: Media {
    @Relationship(deleteRule: .cascade, inverse: \Season.series)
    var seasons: [Season] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Episode.series)
    var episodes: [Episode] = []
    
    init(name: String, sourceId: Int, tmdbId: String? = nil, rating: Double? = nil, trailer: String? = nil, cover: URL? = nil, added: Date, isFavorite: Bool = false, category: Category, info: MediaInfo? = nil, activity: WatchActivity? = nil, source: MediaSource!, download: Download? = nil, seasons: [Season], episodes: [Episode]) {
        self.seasons = seasons
        self.episodes = episodes
        super.init(name: name, sourceId: sourceId, added: added, isFavorite: isFavorite, category: category)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Season: Media {
    var seasonNumber: Int
    
    var series: Series
    
    @Relationship(inverse: \Episode.season)
    var episodes: [Episode] = []
    
    init(name: String, sourceId: Int, tmdbId: String? = nil, rating: Double? = nil, trailer: String? = nil, cover: URL? = nil, added: Date, isFavorite: Bool = false, category: Category, info: MediaInfo? = nil, activity: WatchActivity? = nil, source: MediaSource!, download: Download? = nil, seasonNumber: Int, series: Series, episodes: [Episode]) {
        self.seasonNumber = seasonNumber
        self.series = series
        self.episodes = episodes
        super.init(name: name, sourceId: sourceId, added: added, isFavorite: isFavorite, category: category)
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model final class Episode: PlayableMedia {
    var episodeNumber: Int
    
    var series: Series
    
    var season: Season
    
    init(name: String, sourceId: Int, tmdbId: String? = nil, rating: Double? = nil, trailer: String? = nil, cover: URL? = nil, added: Date, isFavorite: Bool = false, category: Category, info: MediaInfo? = nil, activity: WatchActivity? = nil, source: MediaSource!, download: Download? = nil, episodeNumber: Int, series: Series, season: Season) {
        self.episodeNumber = episodeNumber
        self.series = series
        self.season = season
        super.init(name: name, sourceId: sourceId, added: added, isFavorite: isFavorite, category: category, source: source, download: download)
    }
}
