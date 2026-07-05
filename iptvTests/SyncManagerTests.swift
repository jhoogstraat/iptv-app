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
            let urlConfiguration = URLSessionConfiguration.ephemeral
            urlConfiguration.protocolClasses = [StubXtreamURLProtocol.self]
            let http = HTTPClient(configuration: urlConfiguration)
            
            let syncManager = SyncManager(
                service: XtreamService(
                    client: http,
                    baseURL: try #require(URL(string: "https://example.com")),
                    username: "user",
                    password: "pass",
                ),
                database: database
            )

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
    
    private func withTestDatabase<T>(_ operation: (any DatabaseWriter) async throws -> T) async throws -> T {
        let database = try appDatabase()
        return try await operation(database)
    }
    
    private func resetDatabase(_ database: any DatabaseWriter) throws {
        try database.write { db in
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
                [
                    "stream_id": 2,
                    "num": 2,
                    "name": "Movie Two",
                    "category_id": "200",
                    "stream_icon": "https://example.com/movie-two.jpg",
                    "added": "0",
                    "rating": 7.4,
                    "tmdb": "222",
                    "is_adult": 0,
                ],
            ]
        case "get_series_categories":
            payload = [
                ["category_id": "300", "category_name": "Sci-Fi"],
            ]
        case "get_series":
            payload = [
                [
                    "series_id": 3,
                    "num": 1,
                    "name": "Series One",
                    "category_id": "300",
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
