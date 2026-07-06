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
            initialSyncPhase = .succeeded
            lastErrorMessage = nil
            return .success
        } catch {
            seriesSync = .failure
            initialSyncPhase = .failed
            lastErrorMessage = error.localizedDescription
            logger.warning("Error syncing: \(error.localizedDescription, privacy: .public)")
            return .failure
        }
        
//            do {
//                self.liveSync = .active
//                try await syncLive()
//                self.liveSync = .success
//            } catch {
//                self.liveSync = .failure(error)
//                logger.warning("Error syncing: \(error.localizedDescription, privacy: .public)")
//            }
        
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
                        $0.tmdbID = stream.tmdb
                        $0.coverURL = stream.cover.flatMap(URL.init)
                        $0.rating = stream.rating
                        $0.categoryID = #bind(resolvedCategoryID ?? category)
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
    private func clearCatalog() async throws {
        try await database.write { db in
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
        case succeeded
        case failed
    }
    
    enum SyncError: Error {
        case noSourceIDFound(Category.ID)
        case unknown(Error)
    }
}

private let logger = Logger(subsystem: "IPTV", category: "SyncManager")
