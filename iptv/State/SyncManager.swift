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
    @Dependency(\.defaultDatabase) var database
    
    // State
    var movieSync = SyncState.idle
    var seriesSync = SyncState.idle
    var liveSync = SyncState.idle
    
    init(service: XtreamService) {
        self.service = service
    }

    func sync() async {
        do {
            try await database.write { db in
                try Media.delete().execute(db)
                try Category.delete().execute(db)
            }
        } catch {
            self.movieSync = .failure
            logger.warning("Error deleting stale data: \(error.localizedDescription, privacy: .public)")
        }
        
        do {
            self.movieSync = .active
            try await syncMovieCategories()
            self.movieSync = .success
        } catch {
            self.movieSync = .failure
            logger.warning("Error syncing: \(error.localizedDescription, privacy: .public)")
        }
        
//        do {
//            self.seriesSync = .active
//            try await syncSeries()
//            self.seriesSync = .success
//        } catch {
//            self.seriesSync = .failure
//            logger.warning("Error syncing: \(error.localizedDescription, privacy: .public)")
//        }
//            do {
//                self.liveSync = .active
//                try await syncLive()
//                self.liveSync = .success
//            } catch {
//                self.liveSync = .failure(error)
//                logger.warning("Error syncing: \(error.localizedDescription, privacy: .public)")
//            }
    }

    private func syncMovieCategories() async throws {
        let categories = try await service.getCategories(of: .vod)
//        let streams = try await service.getVodStreams()
        
//        let date = Date.now
        try await database.write { db in
            for category in categories {
                try Category.insert { Category.Draft(from: category, type: .movie) }.execute(db)
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
        let sourceID = try await database.read { db in
            try Category.select(\.sourceID).where { $0.id.eq(category) }.fetchOne(db)
        }
        
        guard let sourceID else {
            throw SyncError.noSourceIDFound(category)
        }
        
        let streams = try await service.getVodStreams(in: sourceID)
        
        try await database.write { db in
            for stream in streams {
                try Media.insert {
                    Media.Draft(from: stream, categoryID: category)
                } onConflict: {
                    $0.sourceID
                } doUpdate: {
                    let category: Category.ID? = if let id = stream.categoryId { try? Category.select(\.id).where { $0.sourceID.eq(id) }.fetchOne(db) } else { nil }
                    
                    $0.title = stream.name
                    $0.tmdbID = stream.tmdbId
                    $0.coverURL = URL(string: stream.streamIcon)
                    $0.rating = stream.rating
                    $0.categoryID = #bind(category)
                }.execute(db)
            }
            
            try Category.find(category).update { $0.updatedAt = #sql("datetime()") }.execute(db)
        }
    }
}

extension SyncManager {
    enum SyncState: Equatable {
        case idle, active, success, failure
    }
    
    enum SyncError: Error {
        case noSourceIDFound(Category.ID)
        case unknown(Error)
    }
}

private let logger = Logger(subsystem: "IPTV", category: "SyncManager")
