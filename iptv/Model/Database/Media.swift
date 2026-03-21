//
//  Media.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 16.03.26.
//

import Foundation
import SwiftData

typealias PlayableMedia = Media

@Model
final class MediaInfo: Identifiable {
    var media: Media?

    var plot: String?
    var genre: [String]
    var releaseDate: Date?
    var runtime: Duration?
    var duration: Duration?
    var heroImageURL: URL?
    var backdropURLs: [URL]
    var country: String?
    var director: [String]
    var cast: [String]
    var episodeRuntime: Int?

    init(
        media: Media? = nil,
        plot: String? = nil,
        genre: [String] = [],
        releaseDate: Date? = nil,
        runtime: Duration? = nil,
        duration: Duration? = nil,
        heroImageURL: URL? = nil,
        backdropURLs: [URL] = [],
        country: String? = nil,
        director: [String] = [],
        cast: [String] = [],
        episodeRuntime: Int? = nil
    ) {
        self.media = media
        self.plot = plot
        self.genre = genre
        self.releaseDate = releaseDate
        self.runtime = runtime
        self.duration = duration
        self.heroImageURL = heroImageURL
        self.backdropURLs = backdropURLs
        self.country = country
        self.director = director
        self.cast = cast
        self.episodeRuntime = episodeRuntime
    }
}

@Model
class Media: Identifiable {
    var name: String
    var sourceId: Int
    var tmdbId: String?
    var rating: Double?
    var trailer: String?
    var cover: URL?
    var added: Date
    var isFavorite: Bool

    var category: Category?

    @Relationship(deleteRule: .cascade, inverse: \MediaSource.media)
    var source: MediaSource

    @Relationship(inverse: \Download.media)
    var download: Download?

    @Relationship(deleteRule: .cascade, inverse: \MediaInfo.media)
    var info: MediaInfo?

    @Relationship(deleteRule: .cascade, inverse: \WatchActivity.media)
    var activity: WatchActivity?

    init(
        name: String,
        sourceId: Int,
        tmdbId: String? = nil,
        rating: Double? = nil,
        trailer: String? = nil,
        cover: URL? = nil,
        added: Date,
        isFavorite: Bool = false,
        category: Category? = nil,
        source: MediaSource,
        download: Download? = nil,
        info: MediaInfo? = nil,
        activity: WatchActivity? = nil
    ) {
        self.name = name
        self.sourceId = sourceId
        self.tmdbId = tmdbId
        self.rating = rating
        self.trailer = trailer
        self.cover = cover
        self.added = added
        self.isFavorite = isFavorite
        self.category = category
        self.source = source
        self.download = download
        self.info = info
        self.activity = activity
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model
final class Movie: Media {
    override init(
        name: String,
        sourceId: Int,
        tmdbId: String? = nil,
        rating: Double? = nil,
        trailer: String? = nil,
        cover: URL? = nil,
        added: Date,
        isFavorite: Bool = false,
        category: Category? = nil,
        source: MediaSource,
        download: Download? = nil,
        info: MediaInfo? = nil,
        activity: WatchActivity? = nil
    ) {
        super.init(
            name: name,
            sourceId: sourceId,
            tmdbId: tmdbId,
            rating: rating,
            trailer: trailer,
            cover: cover,
            added: added,
            isFavorite: isFavorite,
            category: category,
            source: source,
            download: download,
            info: info,
            activity: activity
        )
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model
final class Series: Media {
    @Relationship(deleteRule: .cascade, inverse: \Episode.series)
    var episodes: [Episode]

    init(
        name: String,
        sourceId: Int,
        tmdbId: String? = nil,
        rating: Double? = nil,
        trailer: String? = nil,
        cover: URL? = nil,
        added: Date,
        isFavorite: Bool = false,
        category: Category? = nil,
        source: MediaSource,
        download: Download? = nil,
        info: MediaInfo? = nil,
        activity: WatchActivity? = nil,
        episodes: [Episode] = []
    ) {
        self.episodes = episodes
        super.init(
            name: name,
            sourceId: sourceId,
            tmdbId: tmdbId,
            rating: rating,
            trailer: trailer,
            cover: cover,
            added: added,
            isFavorite: isFavorite,
            category: category,
            source: source,
            download: download,
            info: info,
            activity: activity
        )
    }
    
    func season(_ number: Int) -> [Episode] {
        return episodes.filter { $0.season == number }
    }
}

@available(iOS 26, macOS 26, watchOS 26, tvOS 26, *)
@Model
final class Episode: Media {
    var season: Int
    var episode: Int

    var series: Series

    init(
        name: String,
        sourceId: Int,
        tmdbId: String? = nil,
        rating: Double? = nil,
        trailer: String? = nil,
        cover: URL? = nil,
        added: Date,
        isFavorite: Bool = false,
        category: Category? = nil,
        source: MediaSource,
        download: Download? = nil,
        info: MediaInfo? = nil,
        activity: WatchActivity? = nil,
        episode: Int,
        series: Series,
        season: Int
    ) {
        self.season = season
        self.episode = episode
        self.series = series
        super.init(
            name: name,
            sourceId: sourceId,
            tmdbId: tmdbId,
            rating: rating,
            trailer: trailer,
            cover: cover,
            added: added,
            isFavorite: isFavorite,
            category: category,
            source: source,
            download: download,
            info: info,
            activity: activity
        )
    }
}
