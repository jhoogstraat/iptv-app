import Foundation
import Testing

@testable import iptv

@Suite("Media playback source resolver")
struct MediaPlaybackSourceResolverTests {
    @Test func movieURLUsesXtreamMoviePathFromNormalizedProviderEndpoint() throws {
        let resolver = XtreamMediaPlaybackSourceResolver()
        let provider = makeProvider(
            endpoint: try #require(URL(string: "https://stream.example.com:8443")),
            username: "demo-user",
            password: "demo-pass"
        )
        let media = makeMedia(sourceID: 42, type: .movie)

        let url = try resolver.playbackURL(for: media, provider: provider)

        #expect(url.absoluteString == "https://stream.example.com:8443/movie/demo-user/demo-pass/42")
    }

    @Test func movieURLAppendsPersistedContainerExtension() throws {
        let resolver = XtreamMediaPlaybackSourceResolver()
        let provider = makeProvider(
            endpoint: try #require(URL(string: "https://stream.example.com/player_api.php")),
            username: "demo-user",
            password: "demo-pass"
        )
        let media = makeMedia(sourceID: 42, type: .movie, containerExtension: " mkv ")

        let url = try resolver.playbackURL(for: media, provider: provider)

        #expect(url.absoluteString == "https://stream.example.com/movie/demo-user/demo-pass/42.mkv")
    }

    @Test func episodeURLUsesXtreamSeriesPath() throws {
        let resolver = XtreamMediaPlaybackSourceResolver()
        let provider = makeProvider(
            endpoint: try #require(URL(string: "https://stream.example.com")),
            username: "episode-user",
            password: "episode-pass"
        )
        let media = makeMedia(sourceID: 9001, type: .episode)

        let url = try resolver.playbackURL(for: media, provider: provider)

        #expect(url.absoluteString == "https://stream.example.com/series/episode-user/episode-pass/9001")
    }

    @Test func episodeURLAppendsPersistedContainerExtensionWithoutDuplicatingLeadingDot() throws {
        let resolver = XtreamMediaPlaybackSourceResolver()
        let provider = makeProvider(
            endpoint: try #require(URL(string: "https://stream.example.com")),
            username: "episode-user",
            password: "episode-pass"
        )
        let media = makeMedia(sourceID: 9001, type: .episode, containerExtension: ".mp4")

        let url = try resolver.playbackURL(for: media, provider: provider)

        #expect(url.absoluteString == "https://stream.example.com/series/episode-user/episode-pass/9001.mp4")
    }

    @Test func seriesCollectionRowsAreRejectedAsUnsupportedCollections() throws {
        let resolver = XtreamMediaPlaybackSourceResolver()
        let provider = makeProvider(endpoint: try #require(URL(string: "https://stream.example.com")))
        let media = makeMedia(sourceID: 77, type: .series, containerExtension: "mkv")

        do {
            _ = try resolver.playbackURL(for: media, provider: provider)
            Issue.record("Expected series collection rows to be rejected before URL construction.")
        } catch let error as MediaPlaybackSourceResolutionError {
            #expect(error == .unsupportedCollection(.series))
        } catch {
            Issue.record("Expected MediaPlaybackSourceResolutionError.unsupportedCollection(.series), got \(error).")
        }
    }

    private func makeProvider(
        endpoint: URL,
        username: String = "user",
        password: String = "pass"
    ) -> Provider {
        Provider(
            id: 1,
            kind: .xtream,
            name: "Test Provider",
            username: username,
            password: password,
            endpoint: endpoint,
            isInitialized: true,
            isActive: true
        )
    }

    private func makeMedia(sourceID: Int, type: MediaType, containerExtension: String? = nil) -> Media {
        var media = Media(
            id: 1,
            sourceID: sourceID,
            type: type,
            title: "Playable",
            categoryID: nil,
            tmdbID: nil,
            coverURL: nil,
            rating: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        media.containerExtension = containerExtension
        return media
    }
}
