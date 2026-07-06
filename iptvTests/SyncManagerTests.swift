import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing
import xtream_swift

@testable import iptv

@MainActor
@Suite(.serialized)
struct SyncManagerTests {
    @Test func syncPersistsMovieAndSeriesCategories() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(database: database)

            #expect(syncManager.initialSyncPhase == .idle)
            #expect(syncManager.movieSync == .idle)
            #expect(syncManager.seriesSync == .idle)

            let result = await syncManager.sync(provider: Provider.ID())
            
            #expect(result == .success)
            #expect(syncManager.initialSyncPhase == .succeeded)
            #expect(syncManager.movieSync == .success)
            #expect(syncManager.seriesSync == .success)

            let count = try await database.read {
                (try Category.fetchCount($0), try Media.fetchCount($0))
            }
            
            #expect(count.0 == 3)
            #expect(count.1 == 0)
        }
    }

    @Test func categoryHydrationStatesReflectLazyCoverage() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(database: database)
            let result = await syncManager.sync(provider: Provider.ID())
            #expect(result == .success)

            let categories = try await database.read {
                try Category.fetchAll($0)
            }
            let movieCategory = try #require(categories.first { $0.sourceID == "100" && $0.type == .movie })
            let emptyMovieCategory = try #require(categories.first { $0.sourceID == "200" && $0.type == .movie })
            let session = Session(syncManager: syncManager, providerID: Provider.ID(), database: database)

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

    @Test func mediaUpsertsScopeRemoteSourceIDsByType() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let syncManager = try makeSyncManager(database: database)
            let result = await syncManager.sync(provider: Provider.ID())
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
    
    private func makeSyncManager(database: any DatabaseWriter) throws -> SyncManager {
        let urlConfiguration = URLSessionConfiguration.ephemeral
        urlConfiguration.protocolClasses = [StubXtreamURLProtocol.self]
        let http = HTTPClient(configuration: urlConfiguration)

        return SyncManager(
            service: XtreamService(
                client: http,
                baseURL: try #require(URL(string: "https://example.com")),
                username: "user",
                password: "pass",
            ),
            database: database
        )
    }

    private func withTestDatabase<T>(_ operation: (any DatabaseWriter) async throws -> T) async throws -> T {
        let database = try appDatabase()
        return try await operation(database)
    }
    
    private func resetDatabase(_ database: any DatabaseWriter) throws {
        try database.write { db in
            try CategoryPrefixVisibility.delete().execute(db)
            try Media.delete().execute(db)
            try Category.delete().execute(db)
            try Provider.delete().execute(db)
        }
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
