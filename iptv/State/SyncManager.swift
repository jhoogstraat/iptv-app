//
//  Sync.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 19.03.26.
//

import OSLog
import SwiftUI
import xtream_swift
import SQLiteData
import Dependencies
import GRDB

//extension Array {
//    nonisolated func chunked(into size: Int) -> [[Element]] {
//        precondition(size > 0, "Chunk size must be greater than 0")
//
//        var chunks: [[Element]] = []
//        chunks.reserveCapacity((count + size - 1) / size)
//
//        var index = 0
//        while index < count {
//            let end = Swift.min(index + size, count)
//            chunks.append(Array(self[index..<end]))
//            index += size
//        }
//
//        return chunks
//    }
//}

@Observable
final class SyncManager {
        
    // Deps
    private let service: XtreamService

    @ObservationIgnored
    private let database: any DatabaseWriter
    
    // State
    var movieSync = SyncStatus.idle
    var seriesSync = SyncStatus.idle
    var liveSync = SyncStatus.idle
    private(set) var initialSyncPhase: InitialSyncPhase = .idle
    private(set) var lastErrorMessage: String?
    private(set) var categoryHydrationStates: [Category.ID: CategoryHydrationState] = [:]
    
    
    init(service: XtreamService, database: (any DatabaseWriter)? = nil) {
        @Dependency(\.defaultDatabase) var defaultDatabase
        self.service = service
        self.database = database ?? defaultDatabase
    }

    func sync(provider id: Provider.ID) async -> SyncStatus {
        initialSyncPhase = .clearingLibrary
        lastErrorMessage = nil
        movieSync = .idle
        seriesSync = .idle
        liveSync = .idle
        categoryHydrationStates.removeAll()

        do {
            try await clearCatalog()
        } catch {
            movieSync = .failure
            initialSyncPhase = .failed
            lastErrorMessage = error.localizedDescription
            logger.warning("Error deleting stale data: \(error.localizedDescription, privacy: .public)")
            return .failure
        }
        
        do {
            initialSyncPhase = .syncingMovies
            movieSync = .active
            try await syncCategories(.vod)
            movieSync = .success
        } catch {
            movieSync = .failure
            initialSyncPhase = .failed
            lastErrorMessage = error.localizedDescription
            logger.warning("Error syncing: \(error.localizedDescription, privacy: .public)")
            return .failure
        }
        
        do {
            initialSyncPhase = .syncingSeries
            seriesSync = .active
            try await syncCategories(.series)
            seriesSync = .success
        } catch {
            seriesSync = .failure
            initialSyncPhase = .failed
            lastErrorMessage = error.localizedDescription
            logger.warning("Error syncing: \(error.localizedDescription, privacy: .public)")
            return .failure
        }

        do {
            initialSyncPhase = .syncingLive
            liveSync = .active
            try await syncCategories(.live)
            liveSync = .success
            initialSyncPhase = .succeeded
            lastErrorMessage = nil
            return .success
        } catch {
            liveSync = .failure
            initialSyncPhase = .failed
            lastErrorMessage = error.localizedDescription
            logger.warning("Error syncing: \(error.localizedDescription, privacy: .public)")
            return .failure
        }
        
        
    }

    private func syncCategories(_ type: Xtream.ContentType) async throws {
        let categories = try await service.getCategories(of: type)
        try await database.write { db in
            for category in categories {
                try Category.insert {
                    Category.Draft(from: category, type: type)
                } onConflict: {
                    ($0.sourceID, $0.type)
                } doUpdate: {
                    $0.title = category.name
                }.execute(db)
            }
            
            // Does a lot of type checks (ca. 11s)
            // Also, foreign key reference to category is not resolved
//            for chunk in streams.map { Media.Draft(from: $0) }.chunked(into: 4000) {
//                try Media.insert { chunk }.execute(db)
//            }

            // Much faster, but no checks (ca. 1,6s)
//            let statement = try db.makeStatement(sql: """
//                INSERT into "media" ("sourceID", "type", "title", "tmdbID", "coverURL", "rating", "categoryID")
//                VALUES (?, ?, ?, ?, ?, ?, (SELECT "id" FROM "categories" WHERE "sourceID" = ?))
//                """)
//            for stream in streams {
//                try statement.execute(arguments: [
//                    stream.id,
//                    MediaType.movie.rawValue,
//                    stream.name,
//                    stream.tmdbId,
//                    stream.streamIcon,
//                    stream.rating,
//                    stream.categoryId,
//                ])
//            }
        }
        
//        let duration = Date.now.timeIntervalSince(date)
//        logger.info("elapsed time: \(duration)s")
    }
    
    func updateMovies(in category: Category.ID) async throws {
        categoryHydrationStates[category] = .loading

        do {
            let sourceID = try await database.read { db in
                try Category.select(\.sourceID)
                    .where { $0.id.eq(category).and($0.type.eq(MediaType.movie)) }
                    .fetchOne(db)
            }

            guard let sourceID else {
                throw SyncError.noSourceIDFound(category)
            }

            let streams = try await service.getVodStreams(in: sourceID)

            let count = try await database.write { db in
                for stream in streams {
                    let resolvedCategoryID: Category.ID? = if let id = stream.categoryId {
                        try? Category.select(\.id)
                            .where { $0.sourceID.eq(id).and($0.type.eq(MediaType.movie)) }
                            .fetchOne(db)
                    } else {
                        nil
                    }

                    try Media.insert {
                        Media.Draft(from: stream, categoryID: resolvedCategoryID ?? category)
                    } onConflict: {
                        ($0.sourceID, $0.type)
                    } doUpdate: {
                        $0.title = stream.name
                        $0.tmdbID = stream.tmdbId
                        $0.coverURL = URL(string: stream.streamIcon)
                        $0.rating = stream.rating
                        $0.categoryID = #bind(resolvedCategoryID ?? category)
                        $0.containerExtension = XtreamMapper.text(stream.containerExtension)
                        $0.trailer = XtreamMapper.text(stream.trailer)
                        $0.addedAt = XtreamMapper.date(from: stream.added)
                    }.execute(db)
                }

                try Category.find(category).update { $0.updatedAt = #sql("datetime()") }.execute(db)
                return try Media.where { $0.categoryID.eq(category) }.fetchCount(db)
            }

            categoryHydrationStates[category] = count == 0 ? .empty : .populated(count)
        } catch {
            categoryHydrationStates[category] = .failed(error.localizedDescription)
            throw error
        }
    }
    
    func updateSeries(in category: Category.ID) async throws {
        categoryHydrationStates[category] = .loading

        do {
            let sourceID = try await database.read { db in
                try Category.select(\.sourceID)
                    .where { $0.id.eq(category).and($0.type.eq(MediaType.series)) }
                    .fetchOne(db)
            }

            guard let sourceID else {
                throw SyncError.noSourceIDFound(category)
            }

            let streams = try await service.getSeriesStreams(in: sourceID)

            let count = try await database.write { db in
                for stream in streams {
                    let resolvedCategoryID: Category.ID? = if let id = stream.categoryId {
                        try? Category.select(\.id)
                            .where { $0.sourceID.eq(id).and($0.type.eq(MediaType.series)) }
                            .fetchOne(db)
                    } else {
                        nil
                    }

                    try Media.insert {
                        Media.Draft(from: stream, categoryID: resolvedCategoryID ?? category)
                    } onConflict: {
                        ($0.sourceID, $0.type)
                    } doUpdate: {
                        $0.title = stream.name
                        $0.tmdbID = XtreamMapper.text(stream.tmdb)
                        $0.coverURL = XtreamMapper.url(stream.cover)
                        $0.rating = stream.rating
                        $0.categoryID = #bind(resolvedCategoryID ?? category)
                        $0.synopsis = XtreamMapper.text(stream.plot)
                        $0.releaseDate = stream.releaseDate
                        $0.runtimeSeconds = XtreamMapper.runtimeSeconds(fromRuntime: stream.episodeRuntime)
                        $0.cast = XtreamMapper.text(stream.cast)
                        $0.director = XtreamMapper.text(stream.director)
                        $0.trailer = XtreamMapper.text(stream.youtubeTrailer)
                        $0.addedAt = XtreamMapper.date(from: stream.lastModified)
                        $0.backdropURL = XtreamMapper.firstURL(stream.backdropPath)
                    }.execute(db)
                }

                try Category.find(category).update { $0.updatedAt = #sql("datetime()") }.execute(db)
                return try Media.where { $0.categoryID.eq(category) }.fetchCount(db)
            }

            categoryHydrationStates[category] = count == 0 ? .empty : .populated(count)
        } catch {
            categoryHydrationStates[category] = .failed(error.localizedDescription)
            throw error
        }
    }

    func updateLiveChannels(in category: Category.ID) async throws {
        categoryHydrationStates[category] = .loading

        do {
            let sourceID = try await database.read { db in
                try Category.select(\.sourceID)
                    .where { $0.id.eq(category).and($0.type.eq(MediaType.live)) }
                    .fetchOne(db)
            }

            guard let sourceID else {
                throw SyncError.noSourceIDFound(category)
            }

            let streams = try await service.getLiveStreams(in: sourceID)

            let count = try await database.write { db in
                for stream in streams {
                    let resolvedCategoryID: Category.ID? = if let id = stream.categoryId {
                        try? Category.select(\.id)
                            .where { $0.sourceID.eq(id).and($0.type.eq(MediaType.live)) }
                            .fetchOne(db)
                    } else {
                        nil
                    }

                    try Media.insert {
                        Media.Draft(from: stream, categoryID: resolvedCategoryID ?? category)
                    } onConflict: {
                        ($0.sourceID, $0.type)
                    } doUpdate: {
                        $0.title = stream.name
                        $0.categoryID = #bind(resolvedCategoryID ?? category)
                        $0.coverURL = XtreamMapper.url(stream.streamIcon)
                        $0.genre = XtreamMapper.text(stream.streamType)
                        $0.addedAt = XtreamMapper.date(from: stream.added)
                    }.execute(db)
                }

                try Category.find(category).update { $0.updatedAt = #sql("datetime()") }.execute(db)
                return try Media.where { $0.categoryID.eq(category) }.fetchCount(db)
            }

            categoryHydrationStates[category] = count == 0 ? .empty : .populated(count)
        } catch {
            categoryHydrationStates[category] = .failed(error.localizedDescription)
            throw error
        }
    }

    func enrichDetails(for mediaID: Media.ID) async throws {
        let media = try await database.read { db in
            try Media.find(db, key: mediaID)
        }

        switch media.type {
        case .movie:
            try await enrichMovieDetails(media)
        case .series:
            try await enrichSeriesDetails(media)
        case .episode, .live:
            return
        }
    }

    private func enrichMovieDetails(_ movie: Media) async throws {
        let details = try await service.getVodInfo(of: movie.sourceID)

        try await database.write { db in
            let categoryID: Category.ID? = try? Category.select(\.id)
                .where { $0.sourceID.eq(details.data.categoryId).and($0.type.eq(MediaType.movie)) }
                .fetchOne(db)

            try Media.find(movie.id).update {
                $0.title = XtreamMapper.text(details.info.name) ?? movie.title
                $0.categoryID = #bind(categoryID ?? movie.categoryID)
                $0.tmdbID = XtreamMapper.text(details.info.tmdbId) ?? movie.tmdbID
                $0.coverURL = XtreamMapper.url(details.info.movieImage) ?? XtreamMapper.url(details.info.coverBig) ?? movie.coverURL
                $0.rating = details.info.rating ?? movie.rating
                $0.containerExtension = XtreamMapper.text(details.data.containerExtension) ?? movie.containerExtension
                $0.synopsis = XtreamMapper.text(details.info.plot) ?? XtreamMapper.text(details.info.description)
                $0.releaseDate = #bind(details.info.releaseDate)
                $0.runtimeSeconds = XtreamMapper.runtimeSeconds(
                    from: details.info.durationSecs,
                    minutes: details.info.runtime,
                    duration: details.info.duration
                )
                $0.genre = XtreamMapper.text(details.info.genre)
                $0.cast = XtreamMapper.text(details.info.cast) ?? XtreamMapper.text(details.info.actors)
                $0.director = XtreamMapper.text(details.info.director)
                $0.trailer = XtreamMapper.text(details.info.youtubeTrailer) ?? movie.trailer
                $0.addedAt = XtreamMapper.date(from: details.data.added) ?? movie.addedAt
                $0.backdropURL = details.info.backdropPath.lazy.compactMap(URL.init).first ?? movie.backdropURL
                $0.country = XtreamMapper.text(details.info.country)
            }.execute(db)
        }
    }

    private func enrichSeriesDetails(_ series: Media) async throws {
        let details = try await service.getSeriesInfo(of: String(series.sourceID))

        try await database.write { db in
            let categoryID: Category.ID? = try? Category.select(\.id)
                .where { $0.sourceID.eq(details.info.categoryId).and($0.type.eq(MediaType.series)) }
                .fetchOne(db)

            try Media.find(series.id).update {
                $0.title = XtreamMapper.text(details.info.name) ?? series.title
                $0.categoryID = #bind(categoryID ?? series.categoryID)
                $0.tmdbID = XtreamMapper.text(details.info.tmdb) ?? series.tmdbID
                $0.coverURL = XtreamMapper.url(details.info.cover) ?? series.coverURL
                $0.rating = Double(details.info.rating) ?? series.rating
                $0.synopsis = XtreamMapper.text(details.info.plot)
                $0.releaseDate = #bind(details.info.releaseDate)
                $0.runtimeSeconds = XtreamMapper.runtimeSeconds(fromRuntime: details.info.episodeRuntime)
                $0.genre = XtreamMapper.text(details.info.genre)
                $0.cast = XtreamMapper.text(details.info.cast)
                $0.director = XtreamMapper.text(details.info.director)
                $0.trailer = XtreamMapper.text(details.info.youtubeTrailer)
                $0.addedAt = XtreamMapper.date(from: details.info.lastModified) ?? series.addedAt
                $0.backdropURL = details.info.backdropPath.lazy.compactMap(URL.init).first ?? series.backdropURL
            }.execute(db)

            for season in details.seasons {
                try SeriesSeason.insert {
                    SeriesSeason.Draft(from: season, seriesID: series.id)
                } onConflict: {
                    ($0.seriesID, $0.seasonNumber)
                } doUpdate: {
                    $0.title = season.name
                    $0.overview = XtreamMapper.text(season.overview)
                    $0.episodeCount = #bind(season.episodeCount)
                    $0.coverURL = XtreamMapper.url(season.coverBig) ?? XtreamMapper.url(season.cover)
                    $0.releaseDate = XtreamMapper.date(from: season.releaseDate) ?? XtreamMapper.date(from: season.airDate)
                }.execute(db)
            }

            for episodes in details.episodes.values {
                for episode in episodes {
                    guard let draft = Media.Draft(from: episode, series: series, categoryID: categoryID ?? series.categoryID) else {
                        logger.warning("Skipping series episode with non-numeric source id: \(episode.id, privacy: .public)")
                        continue
                    }

                    try Media.insert {
                        draft
                    } onConflict: {
                        ($0.sourceID, $0.type)
                    } doUpdate: {
                        $0.title = episode.title
                        $0.categoryID = #bind(categoryID ?? series.categoryID)
                        $0.tmdbID = XtreamMapper.text(episode.info.tmdbId)
                        $0.coverURL = XtreamMapper.url(episode.info.movieImage)
                        $0.rating = episode.info.rating
                        $0.parentSeriesID = #bind(series.id)
                        $0.seasonNumber = #bind(episode.season)
                        $0.episodeNumber = #bind(episode.episodeNum)
                        $0.containerExtension = XtreamMapper.text(episode.containerExtension)
                        $0.synopsis = XtreamMapper.text(episode.info.overview)
                        $0.releaseDate = XtreamMapper.date(from: episode.info.releaseDate) ?? XtreamMapper.date(from: episode.info.airDate)
                        $0.runtimeSeconds = XtreamMapper.runtimeSeconds(from: episode.info.durationSecs, duration: episode.info.duration)
                        $0.cast = XtreamMapper.text(episode.info.crew)
                        $0.addedAt = XtreamMapper.date(from: episode.added)
                        $0.backdropURL = XtreamMapper.firstURL(episode.info.backdropPath)
                    }.execute(db)
                }
            }
        }
    }
    private func clearCatalog() async throws {
        try await database.write { db in
            try SeriesSeason.delete().execute(db)
            try Media.delete().execute(db)
            try Category.delete().execute(db)
        }
    }
}
extension SyncManager {
    enum SyncStatus: Equatable {
        case idle, active, success, failure
    }

    enum CategoryHydrationState: Equatable, Sendable {
        case unhydrated
        case loading
        case empty
        case populated(Int)
        case failed(String)
    }
    
    enum InitialSyncPhase: Equatable {
        case idle
        case clearingLibrary
        case syncingMovies
        case syncingSeries
        case syncingLive
        case succeeded
        case failed
    }
    
    enum SyncError: Error {
        case noSourceIDFound(Category.ID)
        case unknown(Error)
    }
}

private nonisolated let logger = Logger(subsystem: "IPTV", category: "SyncManager")
