import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing
import xtream_swift

@testable import iptv

@MainActor
@Suite(.dependency(\.defaultDatabase, try appDatabase()))
struct SyncManagerTests {
    @Dependency(\.defaultDatabase) var database
    
    @Test func syncPersistsMoviesAndSeries() async throws {
        let urlConfiguration = URLSessionConfiguration.ephemeral
//        urlConfiguration.protocolClasses = [StubXtreamURLProtocol.self]
        let http = HTTPClient.init(configuration: urlConfiguration)
        
        let syncManager = SyncManager(
            service: XtreamService(
                client: http,
                baseURL: try #require(URL(string: "https://example.com")),
                username: "",
                password: "",
            )
        )

        #expect(syncManager.movieSync == .idle)
        #expect(syncManager.seriesSync == .idle)

        await syncManager.sync(provider: Provider.ID())
        
        #expect(syncManager.movieSync == .success)
//        #expect(syncManager.seriesSync == .success)

        let count = try await database.read {
            (try Category.fetchCount($0), try Media.fetchCount($0))
        }
        
        print(count)
        
        #expect(count.0 > 10)
        #expect(count.1 > 10)
//        let movieCategories = try await database.read {
//            try iptv.Category.where { $0.type.eq(#bind(iptv.MediaType.movie)) }.fetchAll($0)
//        }
//        let seriesCategories = try await database.read {
//            try iptv.Category.where { $0.type.eq(#bind(iptv.MediaType.series)) }.fetchAll($0)
//        }
//        let movies = try await database.read {
//            try iptv.Media.where { $0.type.eq(#bind(iptv.MediaType.movie)) }.fetchAll($0)
//        }
//        let series = try await database.read {
//            try iptv.Media.where { $0.type.eq(#bind(iptv.MediaType.series)) }.fetchAll($0)
//        }

//        #expect(Set(movieCategories.map(\.title)) == ["Action", "Drama"])
//        #expect(Set(seriesCategories.map(\.title)) == ["Sci-Fi"])
//        #expect(Set(movies.map(\.title)) == ["Movie One", "Movie Two"])
//        #expect(Set(series.map(\.title)) == ["Series One"])
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
