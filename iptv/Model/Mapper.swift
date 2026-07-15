//
//  Mapper.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import Foundation
import xtream_swift

enum XtreamMapper {

    nonisolated static func date(from value: String?) -> Date? {
        guard let rawValue = text(value) else { return nil }

        if let unixTimestamp = TimeInterval(rawValue) {
            return Date(timeIntervalSince1970: unixTimestamp)
        }

        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            if let parsedDate = makeFormatter(format).date(from: rawValue) {
                return parsedDate
            }
        }

        return nil
    }

    nonisolated static func runtimeSeconds(from seconds: Int?, minutes: Int? = nil, duration: String? = nil) -> Int? {
        if let seconds, seconds > 0 { return seconds }
        if let minutes, minutes > 0 { return minutes * 60 }
        guard let duration = text(duration) else { return nil }

        if let rawValue = Int(duration), rawValue > 0 {
            return rawValue
        }

        let components = duration
            .split(separator: ":")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        switch components.count {
        case 3:
            return components[0] * 3600 + components[1] * 60 + components[2]
        case 2:
            return components[0] * 60 + components[1]
        default:
            return nil
        }
    }

    nonisolated static func runtimeSeconds(fromRuntime value: String?) -> Int? {
        guard let value = text(value) else { return nil }
        if let minutes = Int(value), minutes > 0 {
            return minutes * 60
        }
        return runtimeSeconds(from: nil, duration: value)
    }

    nonisolated static func text(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }

    nonisolated static func url(_ value: String?) -> URL? {
        text(value).flatMap(URL.init)
    }

    nonisolated static func firstURL(_ values: [String?]?) -> URL? {
        values?
            .lazy
            .compactMap { url($0) }
            .first
    }

    nonisolated private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}

extension Media.Draft {
    nonisolated init(from stream: Xtream.VodStream, categoryID: Category.ID? = nil) {
        self.id = nil
        self.sourceID = stream.id
        self.type = .movie
        self.title = stream.name
        self.categoryID = categoryID
        self.tmdbID = XtreamMapper.text(stream.tmdbId)
        self.coverURL = XtreamMapper.url(stream.streamIcon)
        self.rating = stream.rating
        self.parentSeriesID = nil
        self.seasonNumber = nil
        self.episodeNumber = nil
        self.containerExtension = XtreamMapper.text(stream.containerExtension)
        self.synopsis = nil
        self.releaseDate = nil
        self.runtimeSeconds = nil
        self.genre = nil
        self.cast = nil
        self.director = nil
        self.trailer = XtreamMapper.text(stream.trailer)
        self.addedAt = XtreamMapper.date(from: stream.added)
        self.backdropURL = nil
        self.country = nil
    }
    
    nonisolated init(from stream: Xtream.SeriesStream, categoryID: Category.ID? = nil) {
        self.id = nil
        self.sourceID = stream.id
        self.type = .series
        self.title = stream.name
        self.categoryID = categoryID
        self.tmdbID = XtreamMapper.text(stream.tmdb)
        self.coverURL = XtreamMapper.url(stream.cover)
        self.rating = stream.rating
        self.parentSeriesID = nil
        self.seasonNumber = nil
        self.episodeNumber = nil
        self.containerExtension = nil
        self.synopsis = XtreamMapper.text(stream.plot)
        self.releaseDate = stream.releaseDate
        self.runtimeSeconds = XtreamMapper.runtimeSeconds(fromRuntime: stream.episodeRuntime)
        self.genre = nil
        self.cast = XtreamMapper.text(stream.cast)
        self.director = XtreamMapper.text(stream.director)
        self.trailer = XtreamMapper.text(stream.youtubeTrailer)
        self.addedAt = XtreamMapper.date(from: stream.lastModified)
        self.backdropURL = XtreamMapper.firstURL(stream.backdropPath)
        self.country = nil
    }

    nonisolated init(from stream: Xtream.LiveStream, categoryID: Category.ID? = nil) {
        self.id = nil
        self.sourceID = stream.id
        self.type = .live
        self.title = stream.name
        self.categoryID = categoryID
        self.tmdbID = nil
        self.coverURL = XtreamMapper.url(stream.streamIcon)
        self.rating = nil
        self.parentSeriesID = nil
        self.seasonNumber = nil
        self.episodeNumber = nil
        self.containerExtension = nil
        self.synopsis = nil
        self.releaseDate = nil
        self.runtimeSeconds = nil
        self.genre = XtreamMapper.text(stream.streamType)
        self.cast = nil
        self.director = nil
        self.trailer = nil
        self.addedAt = XtreamMapper.date(from: stream.added)
        self.backdropURL = nil
        self.country = nil
        self.epgChannelID = XtreamMapper.text(stream.epgChannelId)
        self.supportsCatchup = stream.tvArchive == 1
        self.catchupDays = stream.tvArchiveDuration
    }

    nonisolated init?(from episode: Xtream.Episode, series: Media, categoryID: Category.ID? = nil) {
        guard let sourceID = Int(episode.id) ?? episode.info.id else { return nil }

        self.id = nil
        self.sourceID = sourceID
        self.type = .episode
        self.title = episode.title
        self.categoryID = categoryID
        self.tmdbID = XtreamMapper.text(episode.info.tmdbId)
        self.coverURL = XtreamMapper.url(episode.info.movieImage)
        self.rating = episode.info.rating
        self.parentSeriesID = series.id
        self.seasonNumber = episode.season
        self.episodeNumber = episode.episodeNum
        self.containerExtension = XtreamMapper.text(episode.containerExtension)
        self.synopsis = XtreamMapper.text(episode.info.overview)
        self.releaseDate = XtreamMapper.date(from: episode.info.releaseDate) ?? XtreamMapper.date(from: episode.info.airDate)
        self.runtimeSeconds = XtreamMapper.runtimeSeconds(from: episode.info.durationSecs, duration: episode.info.duration)
        self.genre = nil
        self.cast = XtreamMapper.text(episode.info.crew)
        self.director = nil
        self.trailer = nil
        self.addedAt = XtreamMapper.date(from: episode.added)
        self.backdropURL = XtreamMapper.firstURL(episode.info.backdropPath)
        self.country = nil
    }
}

extension SeriesSeason.Draft {
    nonisolated init(from season: Xtream.Season, seriesID: Media.ID) {
        self.id = nil
        self.seriesID = seriesID
        self.seasonNumber = season.seasonNumber
        self.title = season.name
        self.overview = XtreamMapper.text(season.overview)
        self.episodeCount = season.episodeCount
        self.coverURL = XtreamMapper.url(season.coverBig) ?? XtreamMapper.url(season.cover)
        self.releaseDate = XtreamMapper.date(from: season.releaseDate) ?? XtreamMapper.date(from: season.airDate)
    }
}

extension MediaType {
    nonisolated static func from(_ contentType: Xtream.ContentType) -> MediaType {
        switch contentType {
            case .vod: .movie
            case .series: .series
            case .live: .live
        }
    }
}

//extension Episode {
//    convenience init(from stream: Xtream.SeriesStream, category: SeriesCategory?, source: MediaSource, series: Series, season: Int = 1) {
//        self.init(
//            name: stream.name,
//            sourceId: stream.id,
//            tmdbId: stream.tmdb,
//            rating: stream.rating,
//            trailer: stream.youtubeTrailer,
//            cover: stream.cover.flatMap(URL.init),
//            added: XtreamMapper.date(from: stream.lastModified) ?? stream.releaseDate ?? .now,
//            isFavorite: false,
//            category: category,
//            source: source,
//            episode: stream.number ?? 1,
//            series: series,
//            season: season
//        )
//
//        self.info = MediaInfo(media: self, from: stream)
//    }
//
//    convenience init(from episode: Xtream.Episode, category: SeriesCategory?, source: MediaSource, series: Series) {
//        self.init(
//            name: episode.title,
//            sourceId: Int(episode.id) ?? 0,
//            tmdbId: episode.info.tmdbId,
//            rating: episode.info.rating,
//            trailer: nil,
//            cover: episode.info.movieImage.flatMap(URL.init),
//            added: XtreamMapper.date(from: episode.added) ?? .now,
//            isFavorite: false,
//            category: category,
//            source: source,
//            episode: episode.episodeNum,
//            series: series,
//            season: episode.season
//        )
//
//        self.info = MediaInfo(media: self, from: episode.info)
//    }
//}
