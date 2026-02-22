//
//  CoreSpecTests.swift
//  iptvTests
//
//  Created by Codex on 22.02.26.
//

import Foundation
import Testing
@testable import iptv

@MainActor
struct CoreSpecTests {
    @Test
    func backendFactoryPrefersVLCWhenAvailable() {
        let vlc = MockBackend(id: .vlc, canPlayResult: true)
        let av = MockBackend(id: .av, canPlayResult: true)
        let factory = PlaybackBackendFactory(builders: [{ vlc }, { av }])

        let selected = factory.selectBackend(
            for: URL(string: "https://example.com/video.mkv")!,
            contentType: "movie",
            containerExtension: "mkv"
        )

        #expect(selected?.id == .vlc)
    }

    @Test
    func backendFactoryFallsBackWhenPrimaryUnavailable() {
        let unavailableVLC = MockBackend(id: .vlc, isAvailable: false, canPlayResult: true)
        let av = MockBackend(id: .av, canPlayResult: true)
        let factory = PlaybackBackendFactory(builders: [{ unavailableVLC }, { av }])

        let selected = factory.selectBackend(
            for: URL(string: "https://example.com/video.mp4")!,
            contentType: "movie",
            containerExtension: "mp4"
        )

        #expect(selected?.id == .av)
    }

    @Test
    func playerDelegatesTransportAndUpdatesState() async {
        let backend = MockBackend(id: .vlc, canPlayResult: true)
        let factory = PlaybackBackendFactory(builders: [{ backend }])
        let player = Player(backendFactory: factory)
        let video = makeVideo(containerExtension: "mkv")
        let url = URL(string: "https://example.com/movie.mkv")!

        player.load(video, url, presentation: .fullWindow, autoplay: false)
        #expect(backend.loadCallCount == 1)

        player.play()
        player.pause()
        player.togglePlayback()
        player.seek(to: 24)

        #expect(backend.playCallCount == 1)
        #expect(backend.pauseCallCount == 1)
        #expect(backend.toggleCallCount == 1)
        #expect(backend.lastSeekTime == 24)

        backend.emit(.progress(currentTime: 42, duration: 120))
        backend.emit(.playing)
        _ = await waitUntil { player.currentTime == 42 && player.playbackState == .playing }

        #expect(player.currentTime == 42)
        #expect(player.duration == 120)
        #expect(player.playbackState == .playing)
    }

    @Test
    func playerFallsBackFromVLCToAVOnRuntimeFailure() async {
        let vlc = MockBackend(id: .vlc, canPlayResult: true)
        let av = MockBackend(id: .av, canPlayResult: true)
        let factory = PlaybackBackendFactory(builders: [{ vlc }, { av }])
        let player = Player(backendFactory: factory)

        let video = makeVideo(containerExtension: "mkv")
        let url = URL(string: "https://example.com/movie.mkv")!
        player.load(video, url, presentation: .fullWindow, autoplay: true)

        #expect(player.activeBackendID == .vlc)
        #expect(vlc.loadCallCount == 1)

        vlc.emit(.failed(MockError.failed))
        let switched = await waitUntil { player.activeBackendID == .av }

        #expect(switched)
        #expect(av.loadCallCount == 1)
    }

    @Test
    func providerStorePersistsURLInDefaultsAndCredentialsInKeychain() throws {
        let suiteName = "iptv.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = InMemoryKeychainStore()
        let store = ProviderStore(defaults: defaults, keychain: keychain)

        try store.save(
            baseURL: "https://example.com",
            username: "demo-user",
            password: "demo-pass"
        )

        #expect(defaults.string(forKey: "provider.baseURL") == "https://example.com")
        #expect(defaults.string(forKey: "provider.username") == nil)
        #expect(defaults.string(forKey: "provider.password") == nil)
        #expect(keychain.values["provider.username"] == "demo-user")
        #expect(keychain.values["provider.password"] == "demo-pass")

        let config = try #require(try store.configuration())
        #expect(config.apiURL.absoluteString == "https://example.com/player_api.php")
        #expect(config.username == "demo-user")
    }

    @Test
    func mapperHandlesMissingContainerAndRatingMetadata() throws {
        let data = #"""
        {
          "stream_id": 10,
          "name": "Movie",
          "category_id": "1",
          "category_ids": [1],
          "container_extension": null,
          "rating": "",
          "rating_5based": "4.2",
          "stream_type": "movie",
          "tmdb": "",
          "stream_icon": "",
          "added": "2026-01-01",
          "trailer": "",
          "num": 1,
          "is_adult": 0
        }
        """#.data(using: .utf8)!

        let stream = try JSONDecoder().decode(XtreamStream.self, from: data)
        #expect(stream.containerExtension == nil)
        #expect(stream.rating == nil)

        let video = Video(from: stream)
        #expect(video.containerExtension == "mp4")
    }

    @Test
    func cacheManagerDeduplicatesInFlightLoads() async throws {
        let store = InMemoryStreamListCacheStore()
        let manager = CatalogCacheManager(diskStore: store, ttl: 600)
        let key = makeCacheKey()
        let invocationCounter = InvocationCounter()

        async let first: [CachedVideoDTO] = try manager.loadStreamList(for: key) {
            await invocationCounter.increment()
            try await Task.sleep(for: .milliseconds(150))
            return [makeCachedVideo(id: 1)]
        }
        async let second: [CachedVideoDTO] = try manager.loadStreamList(for: key) {
            await invocationCounter.increment()
            return [makeCachedVideo(id: 2)]
        }

        let firstResult = try await first
        let secondResult = try await second

        #expect(firstResult == secondResult)
        #expect(await invocationCounter.value == 1)
    }

    @Test
    func cacheManagerCompletesBackgroundLoadAfterCallerCancellation() async throws {
        let store = InMemoryStreamListCacheStore()
        let manager = CatalogCacheManager(diskStore: store, ttl: 600)
        let key = makeCacheKey()

        let firstLoad = Task {
            try await manager.loadStreamList(for: key) {
                try await Task.sleep(for: .milliseconds(200))
                return [makeCachedVideo(id: 42)]
            }
        }

        try? await Task.sleep(for: .milliseconds(30))
        firstLoad.cancel()
        _ = try? await firstLoad.value

        try? await Task.sleep(for: .milliseconds(260))

        let invocationCounter = InvocationCounter()
        let result = try await manager.loadStreamList(for: key) {
            await invocationCounter.increment()
            throw MockError.failed
        }

        #expect(result.count == 1)
        #expect(result.first?.id == 42)
        #expect(await invocationCounter.value == 0)
    }

    @Test
    func cacheManagerCachesEmptyCategoryResult() async throws {
        let store = InMemoryStreamListCacheStore()
        let manager = CatalogCacheManager(diskStore: store, ttl: 600)
        let key = makeCacheKey()

        let firstResult = try await manager.loadStreamList(for: key) {
            []
        }

        let invocationCounter = InvocationCounter()
        let secondResult = try await manager.loadStreamList(for: key) {
            await invocationCounter.increment()
            throw MockError.failed
        }

        #expect(firstResult.isEmpty)
        #expect(secondResult.isEmpty)
        #expect(await invocationCounter.value == 0)
    }

    private func makeVideo(containerExtension: String) -> Video {
        Video(
            id: 1,
            name: "Test Video",
            containerExtension: containerExtension,
            contentType: "movie",
            coverImageURL: nil,
            tmdbId: nil,
            rating: nil
        )
    }

    private func makeCacheKey() -> StreamListCacheKey {
        StreamListCacheKey(
            providerFingerprint: "provider-fingerprint",
            contentType: .vod,
            categoryID: "1",
            pageToken: nil
        )
    }

    nonisolated private func makeCachedVideo(id: Int) -> CachedVideoDTO {
        CachedVideoDTO(
            id: id,
            name: "Cached \(id)",
            containerExtension: "mp4",
            contentType: "movie",
            coverImageURL: nil,
            tmdbId: nil,
            rating: nil
        )
    }
}

@MainActor
private final class MockBackend: PlaybackBackend {
    let id: PlaybackBackendID
    let isAvailable: Bool
    private let canPlayResult: Bool

    private let stream: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    private(set) var loadCallCount = 0
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var toggleCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastSeekTime: Double?

    init(
        id: PlaybackBackendID,
        isAvailable: Bool = true,
        canPlayResult: Bool
    ) {
        self.id = id
        self.isAvailable = isAvailable
        self.canPlayResult = canPlayResult

        var continuation: AsyncStream<PlaybackEvent>.Continuation?
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation!
    }

    func canPlay(url: URL, contentType: String, containerExtension: String?) -> Bool {
        canPlayResult
    }

    func load(url: URL, autoplay: Bool) throws {
        loadCallCount += 1
    }

    func play() {
        playCallCount += 1
    }

    func pause() {
        pauseCallCount += 1
    }

    func togglePlayback() {
        toggleCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func seek(to seconds: Double) {
        lastSeekTime = seconds
    }

    func events() -> AsyncStream<PlaybackEvent> {
        stream
    }

    func emit(_ event: PlaybackEvent) {
        continuation.yield(event)
    }
}

private enum MockError: Error {
    case failed
}

private final class InMemoryKeychainStore: KeychainStoring {
    var values: [String: String] = [:]

    func set(_ value: String, for key: String) throws {
        values[key] = value
    }

    func get(_ key: String) throws -> String? {
        values[key]
    }

    func delete(_ key: String) throws {
        values.removeValue(forKey: key)
    }
}

private actor InMemoryStreamListCacheStore: StreamListCacheStore {
    private var storage: [String: StreamListCacheEntry] = [:]

    func load(key: StreamListCacheKey) async throws -> StreamListCacheEntry? {
        let rawKey = await key.rawKey
        return storage[rawKey]
    }

    func save(_ entry: StreamListCacheEntry, for key: StreamListCacheKey) async throws {
        let rawKey = await key.rawKey
        storage[rawKey] = entry
    }

    func pruneCacheIfNeeded() async throws { }

    func removeAll(for providerFingerprint: String) async throws { storage.removeAll() }
}

private actor InvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    interval: Duration = .milliseconds(25),
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: interval)
    }
    return await condition()
}
