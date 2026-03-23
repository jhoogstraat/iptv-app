//
//  Mapper.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import Foundation
import xtream_swift

//private enum XtreamMapper {
//    static let timestampFormatters: [DateFormatter] = [
//        makeFormatter("yyyy-MM-dd HH:mm:ss"),
//        makeFormatter("yyyy-MM-dd")
//    ]
//
//    static func date(from value: String?) -> Date? {
//        guard let rawValue = value?.trimmed, !rawValue.isEmpty else {
//            return nil
//        }
//
//        if let unixTimestamp = TimeInterval(rawValue) {
//            return Date(timeIntervalSince1970: unixTimestamp)
//        }
//
//        for formatter in timestampFormatters {
//            if let parsedDate = formatter.date(from: rawValue) {
//                return parsedDate
//            }
//        }
//
//        return nil
//    }
//
//    static func duration(minutes: Int?) -> Duration? {
//        guard let minutes else { return nil }
//        return Duration(secondsComponent: Int64(minutes * 60), attosecondsComponent: 0)
//    }
//
//    static func duration(seconds: Int?) -> Duration? {
//        guard let seconds else { return nil }
//        return Duration(secondsComponent: Int64(seconds), attosecondsComponent: 0)
//    }
//
//    static func parseList(_ value: String?) -> [String] {
//        guard let value else { return [] }
//
//        return value
//            .split(separator: ",")
//            .map(\.trimmed)
//            .filter { !$0.isEmpty }
//    }
//
//    static func text(_ value: String?) -> String? {
//        guard let value = value?.trimmed, !value.isEmpty else {
//            return nil
//        }
//
//        return value
//    }
//
//    private static func makeFormatter(_ format: String) -> DateFormatter {
//        let formatter = DateFormatter()
//        formatter.calendar = Calendar(identifier: .gregorian)
//        formatter.locale = Locale(identifier: "en_US_POSIX")
//        formatter.timeZone = TimeZone(secondsFromGMT: 0)
//        formatter.dateFormat = format
//        return formatter
//    }
//}

extension Media.Draft {
    nonisolated init(from stream: Xtream.VodStream, categoryID: Category.ID? = nil) {
        self.id = nil
        self.sourceID = stream.id
        self.type = .movie
        self.title = stream.name
        self.categoryID = categoryID
        self.tmdbID = stream.tmdbId
        self.coverURL = URL(string: stream.streamIcon)
        self.rating = stream.rating
    }
    
    nonisolated init(from stream: Xtream.SeriesStream, categoryID: Category.ID? = nil) {
        self.id = nil
        self.sourceID = stream.id
        self.type = .series
        self.title = stream.name
        self.categoryID = categoryID
        self.tmdbID = stream.tmdb
        self.coverURL = stream.cover.flatMap(URL.init)
        self.rating = stream.rating
    }
}

extension Category.Draft {
    nonisolated init(from category: Xtream.Category, type: MediaType) {
        self.id = nil
        self.sourceID = category.id
        self.type = type
        self.title = category.name
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
