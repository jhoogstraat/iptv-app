//
//  Mapper.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import Foundation

extension MovieCategory {
    convenience init(from xtream: Xtream.Category) {
        self.init(remoteId: xtream.id, name: xtream.name, group: nil, movies: [])
    }
}

extension SeriesCategory {
    convenience init(from xtream: Xtream.Category) {
        self.init(remoteId: xtream.id, name: xtream.name, group: nil, series: [])
    }
}

extension Movie {
//    convenience init(from stream: Xtream.MovieStream, category: MovieCategory) {
//        
//    }
    
//    convenience init(from stream: Xtream.MovieStream, movie: Xtream.Movie, category: MovieCategory, source: MediaSource) {
//        let info = movie.info
//        let data = movie.data
//
//        self.init(
//            name: info.name.trimmed,
//            plot: info.plot.trimmed,
//            runtime: info.runtime.flatMap { Duration(secondsComponent: Int64($0), attosecondsComponent: 0) },
//            releaseDate: info.releaseDate,
//            ageRating: info.age.trimmed,
//            country: info.country.trimmed,
//            originalName: info.originalName.trimmed,
//            detailsDescription: info.description.trimmed,
//            director: info.director.split(separator: ",").map { $0.trimmed },
//            cast: info.cast.split(separator: ",").map { $0.trimmed },
//            actors: info.actors.split(separator: ",").map { $0.trimmed },
//            rating: info.rating,
//            genre: info.genre.split(separator: ",").map { $0.trimmed },
//            language: nil,
//            backdropURLs: info.backdropPath.compactMap(URL.init),
//            durationSeconds: info.durationSecs ?? info.runtime.map { $0 * 60 },
//            durationFormatted: info.duration.trimmed,
//            episodeRuntime: info.episodeRuntime,
//            mpaaRating: info.mpaaRating,
//            status: info.status,
//            youtubeTrailer: info.youtubeTrailer.flatMap(URL.init),
//            sourceId: data.streamId,
//            tmdbId: stream.tmdbId ?? info.tmdbId,
//            cover: URL(string: info.coverBig),
//            heroImageURL: URL(string: info.movieImage),
//            activity: nil,
//            category: category,
//            isFavorite: false,
//            added: DateFormatter().date(from: data.added) ?? .now,
//            source: source,
//            streamIconURL: URL(string: stream.streamIcon),
//            streamIsAdult: stream.isAdult != 0,
//            streamOrder: stream.num
//        )
//    }
}
