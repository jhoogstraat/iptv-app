import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing
import xtream_swift

@testable import iptv

@MainActor
@Suite(.serialized)
struct SyncManagerTests {
    @Test func syncPersistsMovieSeriesAndLiveCategories() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(database: database)

            #expect(syncManager.initialSyncPhase == .idle)
            #expect(syncManager.movieSync == .idle)
            #expect(syncManager.seriesSync == .idle)
            #expect(syncManager.liveSync == .idle)

            let result = await syncManager.sync()
            
            #expect(result == .success)
            #expect(syncManager.initialSyncPhase == .succeeded)
            #expect(syncManager.movieSync == .success)
            #expect(syncManager.seriesSync == .success)
            #expect(syncManager.liveSync == .success)

            let (categories, mediaCount) = try await database.read {
                (try Category.fetchAll($0), try Media.fetchCount($0))
            }
            let movieCategories = categories.filter { $0.type == .movie }.sorted { $0.sourceID < $1.sourceID }
            let seriesCategories = categories.filter { $0.type == .series }.sorted { $0.sourceID < $1.sourceID }
            let liveCategories = categories.filter { $0.type == .live }.sorted { $0.sourceID < $1.sourceID }
            
            #expect(movieCategories.map(\.sourceID) == ["100", "200"])
            #expect(seriesCategories.map(\.sourceID) == ["100"])
            #expect(liveCategories.map(\.sourceID) == ["300", "400"])
            #expect(liveCategories.map(\.title) == ["Live News", "Sports Live"])
            #expect(mediaCount == 0)
        }
    }

    @Test func duplicateCallersJoinActiveSyncHydrationAndDetailWork() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(database: database)

            async let firstSync = syncManager.sync()
            async let secondSync = syncManager.sync()
            let syncResults = await (firstSync, secondSync)
            #expect(syncResults.0 == .success)
            #expect(syncResults.1 == .success)

            let movieCategory = try await database.read { db in
                let category = try Category.where {
                    $0.sourceID.eq("100").and($0.type.eq(MediaType.movie))
                }.fetchOne(db)
                return try #require(category)
            }

            async let firstHydration: Void = syncManager.updateMovies(in: movieCategory.id)
            async let secondHydration: Void = syncManager.updateMovies(in: movieCategory.id)
            _ = try await (firstHydration, secondHydration)

            let movie = try await database.read { db in
                let media = try Media.where {
                    $0.sourceID.eq(1).and($0.type.eq(MediaType.movie))
                }.fetchOne(db)
                return try #require(media)
            }

            async let firstDetail: Void = syncManager.enrichDetails(for: movie.id)
            async let secondDetail: Void = syncManager.enrichDetails(for: movie.id)
            _ = try await (firstDetail, secondDetail)

            let persistedMovie = try await database.read { db in
                try Media.find(db, key: movie.id)
            }
            #expect(persistedMovie.title == "Detailed Movie")
        }
    }

    @Test func syncStopsWhenProviderSiteDoesNotRespond() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(
                database: database,
                protocolClass: UnresponsiveXtreamURLProtocol.self,
                providerResponseTimeout: .milliseconds(20)
            )

            let result = await syncManager.sync()

            #expect(result == .failure)
            #expect(syncManager.initialSyncPhase == .failed)
            #expect(syncManager.movieSync == .failure)
            #expect(syncManager.lastErrorMessage == "The provider site did not respond. Check the URL and your connection, then try again.")
        }
    }

    @Test func syncStopsAsSoonAsProxyReturnsBadGateway() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let clock = ContinuousClock()
            let startedAt = clock.now
            let syncManager = try makeSyncManager(
                database: database,
                protocolClass: BadGatewayXtreamURLProtocol.self,
                providerResponseTimeout: .seconds(5)
            )

            let result = await syncManager.sync()

            #expect(result == .failure)
            #expect(clock.now - startedAt < .seconds(1))
            #expect(syncManager.initialSyncPhase == .failed)
            #expect(syncManager.movieSync == .failure)
            #expect(syncManager.lastErrorMessage == "The provider site could not be reached (HTTP 502). Check the URL and provider availability, then try again.")
        }
    }

    @Test func syncStopsWhenProviderStopsSendingCatalogData() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(
                database: database,
                protocolClass: StalledSeriesXtreamURLProtocol.self,
                catalogResponseTimeout: .milliseconds(20)
            )

            let result = await syncManager.sync()

            #expect(result == .failure)
            #expect(syncManager.initialSyncPhase == .failed)
            #expect(syncManager.movieSync == .success)
            #expect(syncManager.seriesSync == .failure)
            #expect(syncManager.lastErrorMessage == "The provider stopped sending data while syncing series categories. Try again or check the provider service.")
        }
    }

    @Test func syncRejectsReachableProviderWithNoCatalogData() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(
                database: database,
                protocolClass: EmptyCatalogXtreamURLProtocol.self
            )

            let result = await syncManager.sync()

            #expect(result == .failure)
            #expect(syncManager.initialSyncPhase == .failed)
            #expect(syncManager.movieSync == .failure)
            #expect(syncManager.seriesSync == .failure)
            #expect(syncManager.liveSync == .failure)
            #expect(syncManager.lastErrorMessage == "The provider responded but returned no movie, series, or live categories. Check the credentials and subscription, then try again.")
        }
    }

    @Test func categoryHydrationStatesReflectLazyCoverage() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(database: database)
            let result = await syncManager.sync()
            #expect(result == .success)

            let categories = try await database.read {
                try Category.fetchAll($0)
            }
            let movieCategory = try #require(categories.first { $0.sourceID == "100" && $0.type == .movie })
            let emptyMovieCategory = try #require(categories.first { $0.sourceID == "200" && $0.type == .movie })
            let session = Session(syncManager: syncManager, providerID: 1, database: database)

            #expect(session.hydrationState(for: movieCategory) == .unhydrated)

            try await syncManager.updateMovies(in: movieCategory.id)
            #expect(session.hydrationState(for: movieCategory) == .populated(1))

            try await syncManager.updateMovies(in: emptyMovieCategory.id)
            #expect(session.hydrationState(for: emptyMovieCategory) == .empty)

            do {
                try await syncManager.updateMovies(in: Category.ID(-1))
            } catch {
                // Expected: missing categories expose a failed state for consumers.
            }

            guard case .failed = syncManager.categoryHydrationStates[Category.ID(-1)] else {
                Issue.record("Missing category did not record a failed hydration state")
                return
            }
        }
    }

    @Test func liveCategoryHydrationPersistsChannelsWithLocalMetadata() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(database: database)
            let result = await syncManager.sync()
            #expect(result == .success)

            let liveCategory = try await database.read { db in
                let category = try Category.where { $0.sourceID.eq("300").and($0.type.eq(MediaType.live)) }.fetchOne(db)
                return try #require(category)
            }
            let session = Session(syncManager: syncManager, providerID: 1, database: database)

            #expect(session.hydrationState(for: liveCategory) == .unhydrated)

            try await syncManager.updateLiveChannels(in: liveCategory.id)

            #expect(session.hydrationState(for: liveCategory) == .populated(1))

            let channels = try await database.read { db in
                try Media.where { $0.type.eq(MediaType.live) }.fetchAll(db)
            }
            #expect(channels.count == 1)
            let channel = try #require(channels.first)

            #expect(channel.sourceID == 7001)
            #expect(channel.title == "News 24")
            #expect(channel.categoryID == liveCategory.id)
            #expect(channel.coverURL == URL(string: "https://example.com/news-24.png"))
            #expect(channel.addedAt == Date(timeIntervalSince1970: 1_710_000_000))
            #expect(channel.genre == "live")
            #expect(channel.containerExtension == nil)
            #expect(channel.synopsis == nil)
            #expect(channel.runtimeSeconds == nil)
        }
    }

    @Test func mediaUpsertsScopeRemoteSourceIDsByType() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(database: database)
            let result = await syncManager.sync()
            #expect(result == .success)

            let categories = try await database.read {
                try Category.fetchAll($0)
            }
            let movieCategory = try #require(categories.first { $0.sourceID == "100" && $0.type == .movie })
            let seriesCategory = try #require(categories.first { $0.sourceID == "100" && $0.type == .series })

            try await syncManager.updateMovies(in: movieCategory.id)
            try await syncManager.updateSeries(in: seriesCategory.id)

            let matchingMedia = try await database.read {
                try Media.where { $0.sourceID.eq(1) }.fetchAll($0)
            }

            #expect(matchingMedia.count == 2)
            #expect(Set(matchingMedia.map(\.type)) == [.movie, .series])
            #expect(Set(matchingMedia.compactMap(\.categoryID)) == [movieCategory.id, seriesCategory.id])
        }
    }

    @Test func movieDetailEnrichmentPersistsReliableMetadataAndLeavesBlankTextNil() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(database: database)
            let result = await syncManager.sync()
            #expect(result == .success)

            let movieCategory = try await database.read { db in
                let category = try Category.where { $0.sourceID.eq("100").and($0.type.eq(MediaType.movie)) }.fetchOne(db)
                return try #require(category)
            }
            try await syncManager.updateMovies(in: movieCategory.id)

            let movie = try await database.read { db in
                let media = try Media.where { $0.sourceID.eq(1).and($0.type.eq(MediaType.movie)) }.fetchOne(db)
                return try #require(media)
            }
            try await syncManager.enrichDetails(for: movie.id)

            let enriched = try await database.read { db in
                let media = try Media.where { $0.sourceID.eq(1).and($0.type.eq(MediaType.movie)) }.fetchOne(db)
                return try #require(media)
            }

            #expect(enriched.title == "Detailed Movie")
            #expect(enriched.categoryID == movieCategory.id)
            #expect(enriched.tmdbID == "444")
            #expect(enriched.coverURL == URL(string: "https://example.com/movie-detail.jpg"))
            #expect(enriched.rating == 8.7)
            #expect(enriched.containerExtension == "mkv")
            #expect(enriched.synopsis == "Detailed plot.")
            #expect(enriched.releaseDate == date(year: 2024, month: 2, day: 3))
            #expect(enriched.runtimeSeconds == 5_400)
            #expect(enriched.cast == "Lead Actor")
            #expect(enriched.trailer == "movie-trailer")
            #expect(enriched.addedAt == Date(timeIntervalSince1970: 10))
            #expect(enriched.backdropURL == URL(string: "https://example.com/movie-backdrop.jpg"))
            #expect(enriched.genre == nil)
            #expect(enriched.director == nil)
            #expect(enriched.country == nil)
        }
    }

    @Test func seriesDetailEnrichmentPersistsSeasonsAndPlayableEpisodeRowsLinkedToSeries() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(database: database)
            let result = await syncManager.sync()
            #expect(result == .success)

            let seriesCategory = try await database.read { db in
                let category = try Category.where { $0.sourceID.eq("100").and($0.type.eq(MediaType.series)) }.fetchOne(db)
                return try #require(category)
            }
            try await syncManager.updateSeries(in: seriesCategory.id)

            let series = try await database.read { db in
                let media = try Media.where { $0.sourceID.eq(1).and($0.type.eq(MediaType.series)) }.fetchOne(db)
                return try #require(media)
            }
            try await syncManager.enrichDetails(for: series.id)

            let persistedSeries = try await database.read { db in
                let media = try Media.find(db, key: series.id)
                return try #require(media)
            }
            let seasons = try await database.read { db in
                try SeriesSeason.where { $0.seriesID.eq(series.id) }.order(by: \.seasonNumber).fetchAll(db)
            }
            let episodes = try await database.read { db in
                try Media.where { $0.parentSeriesID.eq(series.id).and($0.type.eq(MediaType.episode)) }
                    .order(by: \.episodeNumber)
                    .fetchAll(db)
            }

            #expect(persistedSeries.type == .series)
            #expect(persistedSeries.containerExtension == nil)
            #expect(persistedSeries.parentSeriesID == nil)
            #expect(persistedSeries.seasonNumber == nil)
            #expect(persistedSeries.episodeNumber == nil)
            #expect(persistedSeries.synopsis == "Series plot.")
            #expect(persistedSeries.runtimeSeconds == 2_700)

            #expect(seasons.map(\.seasonNumber) == [1, 2])
            #expect(seasons.map(\.title) == ["Season 1", "Season 2"])
            #expect(seasons.map(\.episodeCount) == [2, 1])
            #expect(seasons.first?.overview == "Season one overview.")
            #expect(seasons.first?.releaseDate == date(year: 2024, month: 1, day: 5))

            #expect(episodes.map(\.sourceID) == [9001, 9002])
            #expect(episodes.allSatisfy { $0.type == .episode })
            #expect(episodes.allSatisfy { $0.parentSeriesID == series.id })
            #expect(episodes.allSatisfy { $0.categoryID == seriesCategory.id })
            #expect(episodes.map(\.seasonNumber) == [1, 1])
            #expect(episodes.map(\.episodeNumber) == [1, 2])
            #expect(episodes.map(\.containerExtension) == ["mp4", nil])
            #expect(episodes.first?.title == "Pilot")
            #expect(episodes.first?.synopsis == "Pilot overview.")
            #expect(episodes.first?.runtimeSeconds == 2_700)
            #expect(episodes.first?.releaseDate == date(year: 2024, month: 1, day: 6))
            #expect(episodes.first?.cast == "Episode Crew")
            #expect(episodes.last?.synopsis == nil)
            #expect(episodes.last?.coverURL == nil)
            #expect(episodes.last?.cast == nil)
            #expect(episodes.last?.releaseDate == nil)
        }
    }
    
    private func makeSyncManager(
        database: any DatabaseWriter,
        protocolClass: AnyClass = StubXtreamURLProtocol.self,
        providerResponseTimeout: Duration = .seconds(15),
        catalogResponseTimeout: Duration = .seconds(30)
    ) throws -> SyncManager {
        let urlConfiguration = URLSessionConfiguration.ephemeral
        urlConfiguration.protocolClasses = [protocolClass]
        let http = HTTPClient(configuration: urlConfiguration)

        return SyncManager(
            service: XtreamService(
                client: http,
                baseURL: try #require(URL(string: "https://example.com")),
                username: "user",
                password: "pass",
            ),
            providerID: 1,
            providerEndpoint: try #require(URL(string: "https://example.com")),
            username: "user",
            password: "pass",
            database: database,
            providerProbeConfiguration: urlConfiguration,
            providerResponseTimeout: providerResponseTimeout,
            catalogResponseTimeout: catalogResponseTimeout
        )
    }

    private func withTestDatabase<T>(_ operation: (any DatabaseWriter) async throws -> T) async throws -> T {
        let database = try testAppDatabase()
        return try await operation(database)
    }
    
    private func resetDatabase(_ database: any DatabaseWriter) throws {
        let endpoint = try #require(URL(string: "https://example.com"))
        try database.write { db in
            try SeriesSeason.delete().execute(db)
            try CategoryPrefixVisibility.delete().execute(db)
            try Media.delete().execute(db)
            try Category.delete().execute(db)
            try Provider.delete().execute(db)
            try Provider.insert {
                Provider.Draft(
                    id: 1,
                    kind: .xtream,
                    name: "Test Provider",
                    username: "user",
                    credentialReference: "sync-tests",
                    endpoint: endpoint,
                    allowsInsecureHTTP: false,
                    isInitialized: true,
                    isActive: true
                )
            }.execute(db)
        }
    }
    
    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }
}

private final class BadGatewayXtreamURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 502,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class UnresponsiveXtreamURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

private final class StalledSeriesXtreamURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard requestAction != "get_series_categories" else { return }
        finish(with: [["category_id": "100", "category_name": "Available"]])
    }

    override func stopLoading() {}
}

private final class EmptyCatalogXtreamURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { finish(with: []) }
    override func stopLoading() {}
}

private extension URLProtocol {
    var requestAction: String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "action" })?
            .value
    }

    func finish(with payload: Any) {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class StubXtreamURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let action = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "action" })?
            .value

        let payload: Any

        switch action {
        case "get_vod_categories":
            payload = [
                ["category_id": "100", "category_name": "Action"],
                ["category_id": "200", "category_name": "Drama"],
            ]
        case "get_vod_streams":
            let categoryID = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "category_id" })?
                .value
            if categoryID == "100" {
                payload = [
                    [
                        "stream_id": 1,
                        "num": 1,
                        "name": "Movie One",
                        "category_id": "100",
                        "stream_icon": "https://example.com/movie-one.jpg",
                        "added": "0",
                        "rating": 8.1,
                        "tmdb": "111",
                        "container_extension": "ts",
                        "is_adult": 0,
                    ],
                ]
            } else {
                payload = []
            }
        case "get_live_categories":
            payload = [
                ["category_id": "300", "category_name": "Live News"],
                ["category_id": "400", "category_name": "Sports Live"],
            ]
        case "get_live_streams":
            let categoryID = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "category_id" })?
                .value
            if categoryID == "300" {
                payload = [
                    [
                        "stream_id": 7001,
                        "num": 1,
                        "name": "News 24",
                        "category_id": "300",
                        "stream_icon": "https://example.com/news-24.png",
                        "added": "1710000000",
                        "stream_type": "live",
                        "is_adult": 0,
                    ],
                ]
            } else {
                payload = []
            }
        case "get_series_categories":
            payload = [
                ["category_id": "100", "category_name": "Sci-Fi"],
            ]
        case "get_series":
            payload = [
                [
                    "series_id": 1,
                    "num": 1,
                    "name": "Series One",
                    "category_id": "100",
                    "cover": "https://example.com/series-one.jpg",
                    "rating": 9.0,
                    "tmdb": "333",
                ],
            ]
        case "get_vod_info":
            payload = [
                "info": [
                    "actors": "",
                    "age": "",
                    "backdrop_path": ["https://example.com/movie-backdrop.jpg"],
                    "bitrate": 0,
                    "cast": "Lead Actor",
                    "country": " ",
                    "cover_big": "https://example.com/movie-cover-big.jpg",
                    "description": "",
                    "director": " ",
                    "duration": "01:30:00",
                    "episode_run_time": 90,
                    "genre": " ",
                    "movie_image": "https://example.com/movie-detail.jpg",
                    "name": "Detailed Movie",
                    "o_name": "Detailed Movie",
                    "plot": "Detailed plot.",
                    "releasedate": "2024-02-03",
                    "youtube_trailer": "movie-trailer",
                    "duration_secs": 5_400,
                    "rating": 8.7,
                    "runtime": 90,
                    "tmdb_id": "444",
                ],
                "movie_data": [
                    "added": "10",
                    "category_id": "100",
                    "container_extension": "mkv",
                    "direct_source": "",
                    "name": "Detailed Movie",
                    "stream_id": 1,
                ],
            ]
        case "get_series_info":
            payload = [
                "seasons": [
                    [
                        "name": "Season 1",
                        "season_number": 1,
                        "episode_count": 2,
                        "overview": "Season one overview.",
                        "air_date": "2024-01-04",
                        "cover": "https://example.com/season-one.jpg",
                        "cover_big": "https://example.com/season-one-big.jpg",
                        "release_date": "2024-01-05",
                    ],
                    [
                        "name": "Season 2",
                        "season_number": 2,
                        "episode_count": 1,
                        "overview": " ",
                        "cover": "",
                        "cover_big": "",
                    ],
                ],
                "info": [
                    "name": "Detailed Series",
                    "cover": "https://example.com/series-detail.jpg",
                    "plot": "Series plot.",
                    "cast": "Series Cast",
                    "director": "Series Director",
                    "genre": "Sci-Fi",
                    "release_date": "2024-01-01",
                    "last_modified": "1704067200",
                    "rating": "9.2",
                    "rating_5_based": "4.6",
                    "backdrop_path": ["https://example.com/series-backdrop.jpg"],
                    "category_id": "100",
                    "tmdb": "555",
                    "youtube_trailer": "series-trailer",
                    "episode_run_time": "45",
                ],
                "episodes": [
                    "1": [
                        [
                            "id": "9001",
                            "episode_num": 1,
                            "title": "Pilot",
                            "container_extension": "mp4",
                            "info": [
                                "air_date": "2024-01-05",
                                "backdrop_path": ["https://example.com/episode-backdrop.jpg"],
                                "crew": "Episode Crew",
                                "rating": 8.8,
                                "id": 9001,
                                "movie_image": "https://example.com/pilot.jpg",
                                "overview": "Pilot overview.",
                                "releasedate": "2024-01-06",
                                "tmdb_id": "episode-9001",
                                "duration_secs": 2_700,
                                "duration": "00:45:00",
                                "bitrate": 900,
                            ],
                            "added": "20",
                            "season": 1,
                            "direct_source": "",
                        ],
                        [
                            "id": "9002",
                            "episode_num": 2,
                            "title": "Second Episode",
                            "container_extension": " ",
                            "info": [
                                "crew": " ",
                                "id": 9002,
                                "movie_image": " ",
                                "overview": " ",
                                "duration": "0",
                                "bitrate": 0,
                            ],
                            "added": "30",
                            "season": 1,
                            "direct_source": "",
                        ],
                    ],
                ],
            ]
        default:
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }

        let data = try! JSONSerialization.data(withJSONObject: payload)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
