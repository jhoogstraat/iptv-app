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

extension Sequence {
    nonisolated func chunked(into size: Int) -> [[Element]] {
        precondition(size > 0, "Chunk size must be greater than 0")

        var result: [[Element]] = []
        var chunk: [Element] = []
        chunk.reserveCapacity(size)

        for element in self {
            chunk.append(element)
            if chunk.count == size {
                result.append(chunk)
                chunk = []
                chunk.reserveCapacity(size)
            }
        }

        if !chunk.isEmpty {
            result.append(chunk)
        }

        return result
    }
}

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
            try await syncMovies()
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

    private func syncMovies() async throws {
        let categories = try await service.getCategories(of: .vod)
        let streams = try await service.getVodStreams()

        let categoriesByRemoteID = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, Category.Draft(from: $0, type: .movie)) }
        )
        
        let mediaDrafts = streams.map { stream in
            let category = stream.categoryId.flatMap { categoriesByRemoteID[$0] }
            return Media.Draft(from: stream, categoryID: category?.id)
        }
        
        
        let start = Date()
        try await database.write { db in
            for category in categoriesByRemoteID.values {
                try Category.insert { category }.execute(db)
            }
            
            for chunk in mediaDrafts.chunked(into: 1000) {
                for media in chunk {
                    try Media.insert { media }.execute(db)
                }
            }
        }
        
        let elapsed = Date().timeIntervalSince(start)
        logger.info("Took \(elapsed) seconds")
    }
    
    private func syncSeries() async throws {
        let categories = try await service.getCategories(of: .series)
        let streams = try await service.getSeriesStreams()

        let categoriesByRemoteID = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, Category.Draft(from: $0, type: .series)) }
        )
        
        let mediaDrafts = streams.map { stream in
            let category = stream.categoryId.flatMap { categoriesByRemoteID[$0] }
            return Media.Draft(from: stream, categoryID: category?.id)
        }

        try await database.write { db in
            for category in categoriesByRemoteID.values {
                try Category.insert { category }.execute(db)
            }
            
            for media in mediaDrafts {
                try Media.insert { media }.execute(db)
            }
        }
    }
}

extension SyncManager {
    enum SyncState: Equatable {
        case idle, active, success, failure
    }
}

private let logger = Logger(subsystem: "IPTV", category: "SyncManager")
