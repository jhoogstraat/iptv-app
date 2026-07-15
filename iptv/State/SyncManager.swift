//
//  Sync.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 19.03.26.
//

import Foundation
import OSLog
import SwiftUI
import xtream_swift
import SQLiteData
import Dependencies
import GRDB

@MainActor
@Observable
final class SyncManager {
    nonisolated private static let defaultProviderResponseTimeout = Duration.seconds(15)
    nonisolated private static let defaultCatalogResponseTimeout = Duration.seconds(30)

    nonisolated final class Ownership: @unchecked Sendable {
        private let lock = NSLock()
        private var current = true
        nonisolated init() {}

        nonisolated var isCurrent: Bool {
            lock.lock()
            defer { lock.unlock() }
            return current
        }

        nonisolated func invalidate() {
            lock.lock()
            current = false
            lock.unlock()
        }

        nonisolated func checkCurrent() throws {
            guard isCurrent else { throw CancellationError() }
        }
    }

    private nonisolated struct CatalogKey: Hashable, Sendable {
        let sourceID: String
        let type: MediaType
    }

    private struct HydrationKey: Hashable, Sendable {
        let categoryID: Category.ID
        let type: MediaType
    }

    private struct InitialFlight {
        let ownership: Ownership
        let task: Task<SyncStatus, Never>
    }

    private struct HydrationFlight {
        let ownership: Ownership
        let task: Task<Int, Error>
        let previousState: CategoryHydrationState?
    }

    private struct DetailFlight {
        let ownership: Ownership
        let task: Task<Void, Error>
    }

    private let service: XtreamService
    private let providerProbe: ProviderEndpointProbe
    private let providerID: Provider.ID
    private let providerResponseTimeout: Duration
    private let catalogResponseTimeout: Duration
    @ObservationIgnored
    private nonisolated let ownership = Ownership()

    @ObservationIgnored
    private let database: any DatabaseWriter

    var movieSync = SyncStatus.idle
    var seriesSync = SyncStatus.idle
    var liveSync = SyncStatus.idle
    private(set) var initialSyncPhase: InitialSyncPhase = .idle
    private(set) var lastErrorMessage: String?
    private(set) var categoryHydrationStates: [Category.ID: CategoryHydrationState] = [:]

    @ObservationIgnored
    private var initialFlight: InitialFlight?
    @ObservationIgnored
    private var hydrationFlights: [HydrationKey: HydrationFlight] = [:]
    @ObservationIgnored
    private var detailFlights: [Media.ID: DetailFlight] = [:]

    nonisolated var isCurrent: Bool { ownership.isCurrent }

    init(
        service: XtreamService,
        providerID: Provider.ID,
        providerEndpoint: URL,
        username: String,
        password: String,
        database: (any DatabaseWriter)? = nil,
        providerProbeConfiguration: URLSessionConfiguration = .ephemeral,
        providerResponseTimeout: Duration = SyncManager.defaultProviderResponseTimeout,
        catalogResponseTimeout: Duration = SyncManager.defaultCatalogResponseTimeout
    ) {
        @Dependency(\.defaultDatabase) var defaultDatabase
        self.service = service
        self.providerProbe = ProviderEndpointProbe(
            endpoint: providerEndpoint,
            username: username,
            password: password,
            configuration: providerProbeConfiguration
        )
        self.providerID = providerID
        self.database = database ?? defaultDatabase
        self.providerResponseTimeout = providerResponseTimeout
        self.catalogResponseTimeout = catalogResponseTimeout
    }

    func invalidate() {
        ownership.invalidate()
        initialFlight?.ownership.invalidate()
        initialFlight?.task.cancel()
        initialFlight = nil

        for flight in hydrationFlights.values {
            flight.ownership.invalidate()
            flight.task.cancel()
        }
        hydrationFlights.removeAll()

        for flight in detailFlights.values {
            flight.ownership.invalidate()
            flight.task.cancel()
        }
        detailFlights.removeAll()
    }

    func sync() async -> SyncStatus {
        if let initialFlight {
            return await initialFlight.task.value
        }

        cancelHydrationFlights()

        let operation = Ownership()
        let task = Task { [weak self] in
            guard let self else { return SyncStatus.idle }
            return await self.performInitialSync(operation: operation)
        }
        initialFlight = InitialFlight(ownership: operation, task: task)

        let result = await task.value

        if initialFlight?.ownership === operation {
            initialFlight = nil
        }
        return result
    }

    private func performInitialSync(operation: Ownership) async -> SyncStatus {
        lastErrorMessage = nil
        movieSync = .active
        seriesSync = .idle
        liveSync = .idle
        initialSyncPhase = .checkingProvider
        categoryHydrationStates.removeAll()

        do {
            try checkCurrent(operation)
            try await checkProviderEndpoint()
            try checkCurrent(operation)

            initialSyncPhase = .syncingMovies
            let movieCategories = try await fetchInitialCategories(
                of: .vod,
                timeout: catalogResponseTimeout,
                timeoutError: .catalogDataTimedOut(family: "movie")
            )
            try checkCurrent(operation)
            movieSync = .success

            seriesSync = .active
            initialSyncPhase = .syncingSeries
            let seriesCategories = try await fetchInitialCategories(
                of: .series,
                timeout: catalogResponseTimeout,
                timeoutError: .catalogDataTimedOut(family: "series")
            )
            try checkCurrent(operation)
            seriesSync = .success

            // Live is a required catalog family. A Live failure leaves the complete
            // previous snapshot in place and fails the initial sync.
            liveSync = .active
            initialSyncPhase = .syncingLive
            let liveCategories = try await fetchInitialCategories(
                of: .live,
                timeout: catalogResponseTimeout,
                timeoutError: .catalogDataTimedOut(family: "live")
            )
            try checkCurrent(operation)
            liveSync = .success

            initialSyncPhase = .validatingCatalog
            guard !movieCategories.isEmpty || !seriesCategories.isEmpty || !liveCategories.isEmpty else {
                throw InitialSyncError.emptyCatalog
            }

            initialSyncPhase = .replacingCatalog
            try await replaceCatalogCategories(
                movie: movieCategories,
                series: seriesCategories,
                live: liveCategories,
                operation: operation
            )
            try checkCurrent(operation)

            initialSyncPhase = .succeeded
            lastErrorMessage = nil
            return .success
        } catch {
            if isCancellation(error, operation: operation) {
                resetInitialSyncAfterCancellation(operation)
                return .idle
            }

            guard ownership.isCurrent, operation.isCurrent else { return .idle }
            if error as? InitialSyncError == .emptyCatalog {
                movieSync = .failure
                seriesSync = .failure
                liveSync = .failure
            } else {
                if movieSync == .active { movieSync = .failure }
                if seriesSync == .active { seriesSync = .failure }
                if liveSync == .active { liveSync = .failure }
            }
            initialSyncPhase = .failed
            lastErrorMessage = error.localizedDescription
            logger.warning("Initial catalog sync failed: \(error.localizedDescription, privacy: .public)")
            return .failure
        }
    }

    private func checkProviderEndpoint() async throws {
        let providerProbe = providerProbe
        let timeout = providerResponseTimeout

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await providerProbe.check()
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw InitialSyncError.providerDidNotRespond
                }

                defer { group.cancelAll() }
                _ = try await group.next()
            }
        } catch let error as URLError where error.code != .cancelled {
            throw InitialSyncError.providerDidNotRespond
        }
    }

    private func fetchInitialCategories(
        of type: Xtream.ContentType,
        timeout: Duration,
        timeoutError: InitialSyncError
    ) async throws -> [Xtream.Category] {
        let service = service

        return try await withThrowingTaskGroup(of: [Xtream.Category].self) { group in
            group.addTask {
                try await service.getCategories(of: type)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw timeoutError
            }

            defer { group.cancelAll() }
            guard let categories = try await group.next() else {
                throw CancellationError()
            }
            return categories
        }
    }

    private func replaceCatalogCategories(
        movie: [Xtream.Category],
        series: [Xtream.Category],
        live: [Xtream.Category],
        operation: Ownership
    ) async throws {
        let lifetime = ownership
        let providerID = providerID

        try checkCurrent(operation)
        try await database.write { db in
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
            try Self.requireActiveProvider(providerID, in: db)

            var incomingKeys = Set<CatalogKey>()

            for category in movie {
                incomingKeys.insert(CatalogKey(sourceID: category.id, type: .movie))
                try Self.upsertCategory(category, type: .vod, in: db)
            }
            for category in series {
                incomingKeys.insert(CatalogKey(sourceID: category.id, type: .series))
                try Self.upsertCategory(category, type: .series, in: db)
            }
            for category in live {
                incomingKeys.insert(CatalogKey(sourceID: category.id, type: .live))
                try Self.upsertCategory(category, type: .live, in: db)
            }

            let staleCategories = try Category.fetchAll(db).filter {
                !incomingKeys.contains(CatalogKey(sourceID: $0.sourceID, type: $0.type))
            }
            try Self.deleteCatalogRows(for: staleCategories, in: db)
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
        }
    }

    private nonisolated static func upsertCategory(
        _ category: Xtream.Category,
        type: Xtream.ContentType,
        in db: Database
    ) throws {
        try Category.insert {
            Category.Draft(from: category, type: type)
        } onConflict: {
            ($0.sourceID, $0.type)
        } doUpdate: {
            $0.title = category.name
        }.execute(db)
    }

    private nonisolated static func deleteCatalogRows(
        for categories: [Category],
        in db: Database
    ) throws {
        guard !categories.isEmpty else { return }
        let staleCategoryIDs = Set(categories.map(\.id))
        let staleMedia = try Media.fetchAll(db).filter {
            $0.categoryID.map(staleCategoryIDs.contains) == true
        }
        let staleSeriesIDs = Set(staleMedia.filter { $0.type == .series }.map(\.id))

        if !staleSeriesIDs.isEmpty {
            for season in try SeriesSeason.fetchAll(db) where staleSeriesIDs.contains(season.seriesID) {
                try SeriesSeason.find(season.id).delete().execute(db)
            }
            for episode in try Media.fetchAll(db)
                where episode.parentSeriesID.map(staleSeriesIDs.contains) == true {
                try Media.find(episode.id).delete().execute(db)
            }
        }

        for media in staleMedia {
            try Media.find(media.id).delete().execute(db)
        }
        for category in categories {
            try Category.find(category.id).delete().execute(db)
        }
    }

    func updateMovies(in category: Category.ID) async throws {
        try await hydrate(category: category, type: .movie) { [weak self] operation in
            guard let self else { throw CancellationError() }
            return try await self.performMovieHydration(in: category, operation: operation)
        }
    }

    func updateSeries(in category: Category.ID) async throws {
        try await hydrate(category: category, type: .series) { [weak self] operation in
            guard let self else { throw CancellationError() }
            return try await self.performSeriesHydration(in: category, operation: operation)
        }
    }

    func updateLiveChannels(in category: Category.ID) async throws {
        try await hydrate(category: category, type: .live) { [weak self] operation in
            guard let self else { throw CancellationError() }
            return try await self.performLiveHydration(in: category, operation: operation)
        }
    }

    private func hydrate(
        category: Category.ID,
        type: MediaType,
        operation perform: @escaping @MainActor (Ownership) async throws -> Int
    ) async throws {
        let key = HydrationKey(categoryID: category, type: type)
        if let existing = hydrationFlights[key] {
            try await finishHydration(existing, for: key)
            return
        }

        let previousState = categoryHydrationStates[category]
        categoryHydrationStates[category] = .loading
        let operation = Ownership()
        let task = Task {
            try await perform(operation)
        }
        hydrationFlights[key] = HydrationFlight(
            ownership: operation,
            task: task,
            previousState: previousState
        )

        try await finishHydration(
            HydrationFlight(ownership: operation, task: task, previousState: previousState),
            for: key
        )
    }

    private func finishHydration(_ flight: HydrationFlight, for key: HydrationKey) async throws {
        do {
            let count = try await flight.task.value
            if hydrationFlights[key]?.ownership === flight.ownership {
                categoryHydrationStates[key.categoryID] = count == 0 ? .empty : .populated(count)
                hydrationFlights[key] = nil
            }
        } catch {
            if hydrationFlights[key]?.ownership === flight.ownership {
                if isCancellation(error, operation: flight.ownership) {
                    categoryHydrationStates[key.categoryID] = flight.previousState
                } else {
                    categoryHydrationStates[key.categoryID] = .failed(error.localizedDescription)
                }
                hydrationFlights[key] = nil
            }
            throw error
        }
    }

    private func performMovieHydration(
        in category: Category.ID,
        operation: Ownership
    ) async throws -> Int {
        let sourceID = try await categorySourceID(category, type: .movie, operation: operation)
        let streams = try await service.getVodStreams(in: sourceID)
        try checkCurrent(operation)

        let lifetime = ownership
        let providerID = providerID
        return try await database.write { db in
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
            try Self.requireActiveProvider(providerID, in: db)

            let categoryBySourceID = Dictionary(
                try Category.where { $0.type.eq(MediaType.movie) }.fetchAll(db)
                    .map { ($0.sourceID, $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
            let now = Date()
            let incomingSourceIDs = Set(streams.map(\.id))

            for stream in streams {
                let resolvedCategoryID = stream.categoryId.flatMap { categoryBySourceID[$0] } ?? category
                try Media.insert {
                    Media.Draft(from: stream, categoryID: resolvedCategoryID)
                } onConflict: {
                    ($0.sourceID, $0.type)
                } doUpdate: {
                    $0.title = stream.name
                    $0.tmdbID = stream.tmdbId
                    $0.coverURL = URL(string: stream.streamIcon)
                    $0.rating = stream.rating
                    $0.categoryID = #bind(resolvedCategoryID)
                    $0.containerExtension = XtreamMapper.text(stream.containerExtension)
                    $0.trailer = XtreamMapper.text(stream.trailer)
                    $0.addedAt = XtreamMapper.date(from: stream.added)
                    $0.updatedAt = now
                }.execute(db)
            }

            let staleRows = try Media.where {
                $0.type.eq(MediaType.movie).and($0.categoryID.eq(category))
            }.fetchAll(db).filter { !incomingSourceIDs.contains($0.sourceID) }
            for row in staleRows {
                try Media.find(row.id).delete().execute(db)
            }

            try Category.find(category).update { $0.updatedAt = #bind(now) }.execute(db)
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
            return try Media.where {
                $0.type.eq(MediaType.movie).and($0.categoryID.eq(category))
            }.fetchCount(db)
        }
    }

    private func performSeriesHydration(
        in category: Category.ID,
        operation: Ownership
    ) async throws -> Int {
        let sourceID = try await categorySourceID(category, type: .series, operation: operation)
        let streams = try await service.getSeriesStreams(in: sourceID)
        try checkCurrent(operation)

        let lifetime = ownership
        let providerID = providerID
        return try await database.write { db in
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
            try Self.requireActiveProvider(providerID, in: db)

            let categoryBySourceID = Dictionary(
                try Category.where { $0.type.eq(MediaType.series) }.fetchAll(db)
                    .map { ($0.sourceID, $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
            let now = Date()
            let incomingSourceIDs = Set(streams.map(\.id))

            for stream in streams {
                let resolvedCategoryID = stream.categoryId.flatMap { categoryBySourceID[$0] } ?? category
                try Media.insert {
                    Media.Draft(from: stream, categoryID: resolvedCategoryID)
                } onConflict: {
                    ($0.sourceID, $0.type)
                } doUpdate: {
                    $0.title = stream.name
                    $0.tmdbID = XtreamMapper.text(stream.tmdb)
                    $0.coverURL = XtreamMapper.url(stream.cover)
                    $0.rating = stream.rating
                    $0.categoryID = #bind(resolvedCategoryID)
                    $0.synopsis = XtreamMapper.text(stream.plot)
                    $0.releaseDate = stream.releaseDate
                    $0.runtimeSeconds = XtreamMapper.runtimeSeconds(fromRuntime: stream.episodeRuntime)
                    $0.cast = XtreamMapper.text(stream.cast)
                    $0.director = XtreamMapper.text(stream.director)
                    $0.trailer = XtreamMapper.text(stream.youtubeTrailer)
                    $0.addedAt = XtreamMapper.date(from: stream.lastModified)
                    $0.backdropURL = XtreamMapper.firstURL(stream.backdropPath)
                    $0.updatedAt = now
                }.execute(db)
            }

            let staleSeries = try Media.where {
                $0.type.eq(MediaType.series).and($0.categoryID.eq(category))
            }.fetchAll(db).filter { !incomingSourceIDs.contains($0.sourceID) }
            try Self.deleteSeriesRows(staleSeries, in: db)

            try Category.find(category).update { $0.updatedAt = #bind(now) }.execute(db)
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
            return try Media.where {
                $0.type.eq(MediaType.series).and($0.categoryID.eq(category))
            }.fetchCount(db)
        }
    }

    private func performLiveHydration(
        in category: Category.ID,
        operation: Ownership
    ) async throws -> Int {
        let sourceID = try await categorySourceID(category, type: .live, operation: operation)
        let streams = try await service.getLiveStreams(in: sourceID)
        try checkCurrent(operation)

        let lifetime = ownership
        let providerID = providerID
        return try await database.write { db in
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
            try Self.requireActiveProvider(providerID, in: db)

            let categoryBySourceID = Dictionary(
                try Category.where { $0.type.eq(MediaType.live) }.fetchAll(db)
                    .map { ($0.sourceID, $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
            let now = Date()
            let incomingSourceIDs = Set(streams.map(\.id))

            for stream in streams {
                let resolvedCategoryID = stream.categoryId.flatMap { categoryBySourceID[$0] } ?? category
                try Media.insert {
                    Media.Draft(from: stream, categoryID: resolvedCategoryID)
                } onConflict: {
                    ($0.sourceID, $0.type)
                } doUpdate: {
                    $0.title = stream.name
                    $0.categoryID = #bind(resolvedCategoryID)
                    $0.coverURL = XtreamMapper.url(stream.streamIcon)
                    $0.genre = XtreamMapper.text(stream.streamType)
                    $0.addedAt = XtreamMapper.date(from: stream.added)
                    $0.epgChannelID = XtreamMapper.text(stream.epgChannelId)
                    $0.supportsCatchup = stream.tvArchive == 1
                    $0.catchupDays = #bind(stream.tvArchiveDuration)
                    $0.updatedAt = now
                }.execute(db)
            }

            let staleRows = try Media.where {
                $0.type.eq(MediaType.live).and($0.categoryID.eq(category))
            }.fetchAll(db).filter { !incomingSourceIDs.contains($0.sourceID) }
            for row in staleRows {
                try Media.find(row.id).delete().execute(db)
            }

            try Category.find(category).update { $0.updatedAt = #bind(now) }.execute(db)
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
            return try Media.where {
                $0.type.eq(MediaType.live).and($0.categoryID.eq(category))
            }.fetchCount(db)
        }
    }

    private func categorySourceID(
        _ category: Category.ID,
        type: MediaType,
        operation: Ownership
    ) async throws -> String {
        try checkCurrent(operation)
        let sourceID = try await database.read { db in
            try Category.select(\.sourceID)
                .where { $0.id.eq(category).and($0.type.eq(type)) }
                .fetchOne(db)
        }
        try checkCurrent(operation)

        guard let sourceID else {
            throw SyncError.noSourceIDFound(category)
        }
        return sourceID
    }

    private nonisolated static func deleteSeriesRows(
        _ seriesRows: [Media],
        in db: Database
    ) throws {
        guard !seriesRows.isEmpty else { return }
        let seriesIDs = Set(seriesRows.map(\.id))

        for season in try SeriesSeason.fetchAll(db) where seriesIDs.contains(season.seriesID) {
            try SeriesSeason.find(season.id).delete().execute(db)
        }
        for episode in try Media.fetchAll(db)
            where episode.parentSeriesID.map(seriesIDs.contains) == true {
            try Media.find(episode.id).delete().execute(db)
        }
        for series in seriesRows {
            try Media.find(series.id).delete().execute(db)
        }
    }

    func enrichDetails(for mediaID: Media.ID) async throws {
        if let existing = detailFlights[mediaID] {
            try await finishDetailEnrichment(existing, for: mediaID)
            return
        }

        let operation = Ownership()
        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.performDetailEnrichment(for: mediaID, operation: operation)
        }
        detailFlights[mediaID] = DetailFlight(ownership: operation, task: task)

        try await finishDetailEnrichment(
            DetailFlight(ownership: operation, task: task),
            for: mediaID
        )
    }

    private func finishDetailEnrichment(_ flight: DetailFlight, for mediaID: Media.ID) async throws {
        do {
            try await flight.task.value
            if detailFlights[mediaID]?.ownership === flight.ownership {
                detailFlights[mediaID] = nil
            }
        } catch {
            if detailFlights[mediaID]?.ownership === flight.ownership {
                detailFlights[mediaID] = nil
            }
            throw error
        }
    }

    private func performDetailEnrichment(
        for mediaID: Media.ID,
        operation: Ownership
    ) async throws {
        try checkCurrent(operation)
        let media = try await database.read { db in
            try Media.find(db, key: mediaID)
        }
        try checkCurrent(operation)

        switch media.type {
        case .movie:
            try await enrichMovieDetails(media, operation: operation)
        case .series:
            try await enrichSeriesDetails(media, operation: operation)
        case .episode, .live:
            return
        }
    }

    private func enrichMovieDetails(
        _ movie: Media,
        operation: Ownership
    ) async throws {
        let details = try await service.getVodInfo(of: movie.sourceID)
        try checkCurrent(operation)

        let lifetime = ownership
        let providerID = providerID
        try await database.write { db in
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
            try Self.requireActiveProvider(providerID, in: db)
            let categoryID = try Category.select(\.id)
                .where {
                    $0.sourceID.eq(details.data.categoryId)
                        .and($0.type.eq(MediaType.movie))
                }
                .fetchOne(db)
            let now = Date()

            try Media.find(movie.id).update {
                $0.title = XtreamMapper.text(details.info.name) ?? movie.title
                $0.categoryID = #bind(categoryID ?? movie.categoryID)
                $0.tmdbID = XtreamMapper.text(details.info.tmdbId) ?? movie.tmdbID
                $0.coverURL = XtreamMapper.url(details.info.movieImage)
                    ?? XtreamMapper.url(details.info.coverBig)
                    ?? movie.coverURL
                $0.rating = details.info.rating ?? movie.rating
                $0.containerExtension = XtreamMapper.text(details.data.containerExtension) ?? movie.containerExtension
                $0.synopsis = XtreamMapper.text(details.info.plot)
                    ?? XtreamMapper.text(details.info.description)
                    ?? movie.synopsis
                $0.releaseDate = #bind(details.info.releaseDate)
                $0.runtimeSeconds = XtreamMapper.runtimeSeconds(
                    from: details.info.durationSecs,
                    minutes: details.info.runtime,
                    duration: details.info.duration
                ) ?? movie.runtimeSeconds
                $0.genre = XtreamMapper.text(details.info.genre) ?? movie.genre
                $0.cast = XtreamMapper.text(details.info.cast)
                    ?? XtreamMapper.text(details.info.actors)
                    ?? movie.cast
                $0.director = XtreamMapper.text(details.info.director) ?? movie.director
                $0.trailer = XtreamMapper.text(details.info.youtubeTrailer) ?? movie.trailer
                $0.addedAt = XtreamMapper.date(from: details.data.added) ?? movie.addedAt
                $0.backdropURL = details.info.backdropPath.lazy.compactMap(URL.init).first ?? movie.backdropURL
                $0.country = XtreamMapper.text(details.info.country) ?? movie.country
                $0.updatedAt = now
            }.execute(db)
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
        }
    }

    private func enrichSeriesDetails(
        _ series: Media,
        operation: Ownership
    ) async throws {
        let details = try await service.getSeriesInfo(of: String(series.sourceID))
        try checkCurrent(operation)

        let lifetime = ownership
        let providerID = providerID
        try await database.write { db in
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
            try Self.requireActiveProvider(providerID, in: db)
            let categoryID = try Category.select(\.id)
                .where {
                    $0.sourceID.eq(details.info.categoryId)
                        .and($0.type.eq(MediaType.series))
                }
                .fetchOne(db)
            let resolvedCategoryID = categoryID ?? series.categoryID
            let now = Date()

            try Media.find(series.id).update {
                $0.title = XtreamMapper.text(details.info.name) ?? series.title
                $0.categoryID = #bind(resolvedCategoryID)
                $0.tmdbID = XtreamMapper.text(details.info.tmdb) ?? series.tmdbID
                $0.coverURL = XtreamMapper.url(details.info.cover) ?? series.coverURL
                $0.rating = Double(details.info.rating) ?? series.rating
                $0.synopsis = XtreamMapper.text(details.info.plot) ?? series.synopsis
                $0.releaseDate = #bind(details.info.releaseDate)
                $0.runtimeSeconds = XtreamMapper.runtimeSeconds(
                    fromRuntime: details.info.episodeRuntime
                ) ?? series.runtimeSeconds
                $0.genre = XtreamMapper.text(details.info.genre) ?? series.genre
                $0.cast = XtreamMapper.text(details.info.cast) ?? series.cast
                $0.director = XtreamMapper.text(details.info.director) ?? series.director
                $0.trailer = XtreamMapper.text(details.info.youtubeTrailer) ?? series.trailer
                $0.addedAt = XtreamMapper.date(from: details.info.lastModified) ?? series.addedAt
                $0.backdropURL = details.info.backdropPath.lazy.compactMap(URL.init).first ?? series.backdropURL
                $0.updatedAt = now
            }.execute(db)

            let existingSeasons = Dictionary(
                try SeriesSeason.where { $0.seriesID.eq(series.id) }.fetchAll(db)
                    .map { ($0.seasonNumber, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let incomingSeasonNumbers = Set(details.seasons.map(\.seasonNumber))
            for season in details.seasons {
                let existing = existingSeasons[season.seasonNumber]
                try SeriesSeason.insert {
                    SeriesSeason.Draft(from: season, seriesID: series.id)
                } onConflict: {
                    ($0.seriesID, $0.seasonNumber)
                } doUpdate: {
                    $0.title = XtreamMapper.text(season.name) ?? existing?.title ?? season.name
                    $0.overview = XtreamMapper.text(season.overview) ?? existing?.overview
                    $0.episodeCount = #bind(season.episodeCount)
                    $0.coverURL = XtreamMapper.url(season.coverBig)
                        ?? XtreamMapper.url(season.cover)
                        ?? existing?.coverURL
                    $0.releaseDate = XtreamMapper.date(from: season.releaseDate)
                        ?? XtreamMapper.date(from: season.airDate)
                        ?? existing?.releaseDate
                    $0.updatedAt = now
                }.execute(db)
            }
            for season in existingSeasons.values
                where !incomingSeasonNumbers.contains(season.seasonNumber) {
                try SeriesSeason.find(season.id).delete().execute(db)
            }

            let existingEpisodes = Dictionary(
                try Media.where {
                    $0.parentSeriesID.eq(series.id).and($0.type.eq(MediaType.episode))
                }.fetchAll(db).map { ($0.sourceID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var incomingEpisodeSourceIDs = Set<Int>()

            for episodes in details.episodes.values {
                for episode in episodes {
                    guard let draft = Media.Draft(
                        from: episode,
                        series: series,
                        categoryID: resolvedCategoryID
                    ) else {
                        logger.warning("Skipping series episode with non-numeric source id: \(episode.id, privacy: .public)")
                        continue
                    }
                    let existing = existingEpisodes[draft.sourceID]
                    incomingEpisodeSourceIDs.insert(draft.sourceID)

                    try Media.insert {
                        draft
                    } onConflict: {
                        ($0.sourceID, $0.type)
                    } doUpdate: {
                        $0.title = XtreamMapper.text(episode.title) ?? existing?.title ?? episode.title
                        $0.categoryID = #bind(resolvedCategoryID)
                        $0.tmdbID = XtreamMapper.text(episode.info.tmdbId) ?? existing?.tmdbID
                        $0.coverURL = XtreamMapper.url(episode.info.movieImage) ?? existing?.coverURL
                        $0.rating = episode.info.rating ?? existing?.rating
                        $0.parentSeriesID = #bind(series.id)
                        $0.seasonNumber = #bind(episode.season)
                        $0.episodeNumber = #bind(episode.episodeNum)
                        $0.containerExtension = XtreamMapper.text(episode.containerExtension)
                            ?? existing?.containerExtension
                        $0.synopsis = XtreamMapper.text(episode.info.overview) ?? existing?.synopsis
                        $0.releaseDate = XtreamMapper.date(from: episode.info.releaseDate)
                            ?? XtreamMapper.date(from: episode.info.airDate)
                            ?? existing?.releaseDate
                        $0.runtimeSeconds = XtreamMapper.runtimeSeconds(
                            from: episode.info.durationSecs,
                            duration: episode.info.duration
                        ) ?? existing?.runtimeSeconds
                        $0.cast = XtreamMapper.text(episode.info.crew) ?? existing?.cast
                        $0.addedAt = XtreamMapper.date(from: episode.added) ?? existing?.addedAt
                        $0.backdropURL = XtreamMapper.firstURL(episode.info.backdropPath)
                            ?? existing?.backdropURL
                        $0.updatedAt = now
                    }.execute(db)
                }
            }

            for episode in existingEpisodes.values
                where !incomingEpisodeSourceIDs.contains(episode.sourceID) {
                try Media.find(episode.id).delete().execute(db)
            }
            try Self.checkCurrent(lifetime: lifetime, operation: operation)
        }
    }

    private func cancelHydrationFlights() {
        for (key, flight) in hydrationFlights {
            flight.ownership.invalidate()
            flight.task.cancel()
            categoryHydrationStates[key.categoryID] = flight.previousState
        }
        hydrationFlights.removeAll()
    }

    private func checkCurrent(_ operation: Ownership) throws {
        try Self.checkCurrent(lifetime: ownership, operation: operation)
    }

    private nonisolated static func checkCurrent(
        lifetime: Ownership,
        operation: Ownership
    ) throws {
        try Task.checkCancellation()
        try lifetime.checkCurrent()
        try operation.checkCurrent()
    }

    private nonisolated static func requireActiveProvider(
        _ providerID: Provider.ID,
        in db: Database
    ) throws {
        let activeProviderID = try Provider.select(\.id)
            .where(\.isActive)
            .fetchOne(db)
        guard activeProviderID == providerID else { throw CancellationError() }
    }

    private func isCancellation(_ error: Error, operation: Ownership) -> Bool {
        error is CancellationError
            || (error as? URLError)?.code == .cancelled
            || !ownership.isCurrent
            || !operation.isCurrent
            || Task.isCancelled
    }

    private func resetInitialSyncAfterCancellation(_ operation: Ownership) {
        guard initialFlight?.ownership === operation || initialFlight == nil else { return }
        movieSync = .idle
        seriesSync = .idle
        liveSync = .idle
        initialSyncPhase = .idle
        lastErrorMessage = nil
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
        case checkingProvider
        case syncingMovies
        case syncingSeries
        case syncingLive
        case validatingCatalog
        case replacingCatalog
        case succeeded
        case failed
    }

    enum InitialSyncError: Error, LocalizedError, Equatable, Sendable {
        case providerDidNotRespond
        case providerHTTPError(statusCode: Int)
        case catalogDataTimedOut(family: String)
        case emptyCatalog

        var errorDescription: String? {
            switch self {
                case .providerDidNotRespond:
                    "The provider site did not respond. Check the URL and your connection, then try again."
                case .providerHTTPError(let statusCode) where [502, 503, 504].contains(statusCode):
                    "The provider site could not be reached (HTTP \(statusCode)). Check the URL and provider availability, then try again."
                case .providerHTTPError(let statusCode):
                    "The provider rejected the initial request (HTTP \(statusCode)). Check the URL and credentials, then try again."
                case .catalogDataTimedOut(let family):
                    "The provider stopped sending data while syncing \(family) categories. Try again or check the provider service."
                case .emptyCatalog:
                    "The provider responded but returned no movie, series, or live categories. Check the credentials and subscription, then try again."
            }
        }
    }

    enum SyncError: Error {
        case noSourceIDFound(Category.ID)
    }
}

private struct ProviderEndpointProbe: Sendable {
    private let request: URLRequest
    private let configuration: URLSessionConfiguration

    init(
        endpoint: URL,
        username: String,
        password: String,
        configuration: URLSessionConfiguration
    ) {
        var components = URLComponents(
            url: XtreamEndpoint.playerAPIURL(from: endpoint),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: "get_vod_categories"),
        ]
        self.request = URLRequest(url: components.url!)

        let configuration = (configuration.copy() as? URLSessionConfiguration) ?? configuration
        configuration.waitsForConnectivity = false
        self.configuration = configuration
    }

    func check() async throws {
        let response = try await ProviderResponseHeaderRequest(
            request: request,
            configuration: configuration
        ).response()
        guard (200..<300).contains(response.statusCode) else {
            throw SyncManager.InitialSyncError.providerHTTPError(
                statusCode: response.statusCode
            )
        }
    }
}

private final class ProviderResponseHeaderRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var isCancelled = false

    init(request: URLRequest, configuration: URLSessionConfiguration) {
        self.request = request
        self.configuration = configuration
    }

    func response() async throws -> HTTPURLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !isCancelled else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }

                self.continuation = continuation
                let session = URLSession(
                    configuration: configuration,
                    delegate: self,
                    delegateQueue: nil
                )
                let task = session.dataTask(with: request)
                self.session = session
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        completionHandler(.cancel)
        guard let response = response as? HTTPURLResponse else {
            finish(.failure(SyncManager.InitialSyncError.providerDidNotRespond))
            return
        }
        finish(.success(response))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error else {
            finish(.failure(SyncManager.InitialSyncError.providerDidNotRespond))
            return
        }
        finish(.failure(error))
    }

    private func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<HTTPURLResponse, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let task = task
        self.task = nil
        let session = session
        self.session = nil
        lock.unlock()

        task?.cancel()
        session?.invalidateAndCancel()
        continuation.resume(with: result)
    }
}

private nonisolated let logger = Logger(subsystem: "IPTV", category: "SyncManager")
