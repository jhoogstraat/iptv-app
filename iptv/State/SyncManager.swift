//
//  Sync.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 19.03.26.
//

import OSLog
import SwiftData
import SwiftUI
import xtream_swift

private enum SyncValueMapper {
    static let liveCategoryPrefix = "live:"

//    static let dateFormatters: [DateFormatter] = [
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
//        for formatter in dateFormatters {
//            if let parsedDate = formatter.date(from: rawValue) {
//                return parsedDate
//            }
//        }
//
//        return nil
//    }

    static func liveCategoryID(for remoteID: String) -> String {
        "\(liveCategoryPrefix)\(remoteID)"
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}

@Observable
final class SyncManager {
    private let container: ModelContainer
    private let provider: Provider
    private let service: XtreamService

    // State
    var movieSync = SyncState.idle
    var seriesSync = SyncState.idle
    var liveSync = SyncState.idle
    
    init(container: ModelContainer, provider: Provider, service: XtreamService) {
        self.container = container
        self.provider = provider
        self.service = service
    }

    func bootstrap() {
        sync()
    }

    func sync() {
        Task {
            do {
                self.movieSync = .active
                try await syncMovies()
                self.movieSync = .success
            } catch {
                self.movieSync = .failure
                logger.warning("Error syncing: \(error.localizedDescription, privacy: .public)")
            }
            
            do {
                self.seriesSync = .active
                try await syncSeries()
                self.seriesSync = .success
            } catch {
                self.seriesSync = .failure
                logger.warning("Error syncing: \(error.localizedDescription, privacy: .public)")
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
    }

    private func syncMovies() async throws {
        let categories = try await service.getCategories(of: .vod)
        let streams = try await service.getVodStreams()

        let movieCategoriesByRemoteID = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, MovieCategory(from: $0)) }
        )

        let context = ModelContext(container)

        try context.transaction {
            try MovieCategory.deleteAll(modelContext: context)

            for category in movieCategoriesByRemoteID.values {
                context.insert(category)
            }

            for stream in streams {
                let category = stream.categoryId.flatMap { movieCategoriesByRemoteID[$0] }
                let source = MediaSource(url: service.getPlayURL(for: stream.id, type: .vod, containerExtension: stream.containerExtension))
                let movie = Movie(from: stream, category: category, source: source)
                context.insert(movie)
            }
        }

        try context.save()
    }

    private func syncSeries() async throws {
        let categories = try await service.getCategories(of: .series)
        let streams = try await service.getSeriesStreams()
        
        let seriesCategoriesByRemoteID = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, SeriesCategory(from: $0)) }
        )
        
        let context = ModelContext(container)
        
        try context.transaction {
            try SeriesCategory.deleteAll(modelContext: context)
            
            for category in seriesCategoriesByRemoteID.values {
                context.insert(category)
            }
            
            for stream in streams {
                let category = stream.categoryId.flatMap { seriesCategoriesByRemoteID[$0] }
                let showSource = MediaSource(
                    url: service.getPlayURL(
                        for: stream.id,
                        type: .series,
                        containerExtension: nil
                    )
                )
                let series = Series(from: stream, category: category, source: showSource)
                
                let episodeSource = MediaSource(
                    url: service.getPlayURL(
                        for: stream.id,
                        type: .series,
                        containerExtension: nil
                    )
                )
                let episode = Episode(from: stream, category: category, source: episodeSource, series: series)
                
                series.episodes = [episode]
                
                context.insert(series)
                context.insert(episode)
            }
        }
        
        try context.save()
    }
}

extension SyncManager {
    enum SyncState: Equatable {
        case idle, active, success, failure
    }
}
