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
    func sleepTimerEndOfItemPausesAndExitsFullWindowPresentation() async {
        let backend = MockBackend(id: .vlc, canPlayResult: true)
        let factory = PlaybackBackendFactory(builders: [{ backend }])
        let player = Player(backendFactory: factory)
        let video = makeVideo(containerExtension: "mkv")
        let url = URL(string: "https://example.com/movie.mkv")!

        player.load(video, url, presentation: .fullWindow, autoplay: false)
        player.setSleepTimer(.endOfItem)
        backend.emit(.ended)

        let slept = await waitUntil {
            player.presentation == .inline && player.sleepTimerOption == .off
        }

        #expect(slept)
        #expect(backend.pauseCallCount == 1)
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
    func providerStorePersistsExcludedPrefixesPerConfiguredProvider() throws {
        let suiteName = "iptv.tests.excluded-prefixes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = InMemoryKeychainStore()
        let store = ProviderStore(defaults: defaults, keychain: keychain)

        try store.save(
            baseURL: "https://example.com",
            username: "demo-user",
            password: "demo-pass"
        )
        try store.saveExcludedCategoryPrefixes(" ar, XXX \n|multi| ")

        #expect(store.excludedCategoryPrefixes() == ["AR", "XXX", "MULTI"])
        #expect(store.excludedCategoryPrefixesInput() == "AR, XXX, MULTI")
        #expect(store.isExcludedCategoryPrefix("ar"))
        #expect(store.isExcludedCategoryPrefix("XXX"))
        #expect(store.isExcludedCategoryPrefix("multi"))
        #expect(store.isExcludedCategoryPrefix("EN") == false)

        let reloaded = ProviderStore(defaults: defaults, keychain: keychain)
        #expect(reloaded.excludedCategoryPrefixes() == ["AR", "XXX", "MULTI"])
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
    func xtreamStreamDecodingAcceptsStringIsAdultValues() throws {
        let data = #"""
        {
          "stream_id": 10,
          "name": "Movie",
          "category_id": "1",
          "category_ids": [1],
          "container_extension": "mkv",
          "rating": "7.1",
          "rating_5based": "4.2",
          "stream_type": "movie",
          "tmdb": "123",
          "stream_icon": "",
          "added": "2026-01-01",
          "trailer": "",
          "num": 1,
          "is_adult": "0"
        }
        """#.data(using: .utf8)!

        let stream = try JSONDecoder().decode(XtreamStream.self, from: data)
        #expect(stream.isAdult == 0)
    }

    @Test
    func xtreamStreamDecodingNormalizesDirtyFields() throws {
        let data = #"""
        {
          "stream_id": "10",
          "name": "  Movie  ",
          "category_id": " 7 ",
          "category_ids": "[7,8,8]",
          "container_extension": "  mkv  ",
          "rating": " 7.1 ",
          "rating_5based": " 4.2 ",
          "stream_type": " Movie ",
          "tmdb": " 123 ",
          "stream_icon": "  https://example.com/poster.jpg  ",
          "added": " 2026-01-01 ",
          "trailer": "  ",
          "num": "1",
          "is_adult": "0"
        }
        """#.data(using: .utf8)!

        let stream = try JSONDecoder().decode(XtreamStream.self, from: data)
        #expect(stream.id == 10)
        #expect(stream.name == "Movie")
        #expect(stream.categoryId == "7")
        #expect(stream.categoryIds == [7, 8])
        #expect(stream.containerExtension == "mkv")
        #expect(stream.rating == 7.1)
        #expect(stream.rating5Based == 4.2)
        #expect(stream.type == "movie")
        #expect(stream.tmdbId == 123)
        #expect(stream.streamIcon == "https://example.com/poster.jpg")
        #expect(stream.added == "2026-01-01")
        #expect(stream.trailer == "")
    }

    @Test
    func xtreamSeriesStreamDecodingNormalizesDirtyFields() throws {
        let data = #"""
        {
          "series_id": "42",
          "name": " ",
          "title": "  Series Title  ",
          "cover": "  https://example.com/cover.jpg  ",
          "rating": " 7.5 ",
          "plot": "  Plot  ",
          "category_id": 3,
          "category_ids": "[3,4,4]"
        }
        """#.data(using: .utf8)!

        let series = try JSONDecoder().decode(XtreamSeriesStream.self, from: data)
        #expect(series.id == 42)
        #expect(series.name == "Series Title")
        #expect(series.cover == "https://example.com/cover.jpg")
        #expect(series.rating == 7.5)
        #expect(series.plot == "Plot")
        #expect(series.categoryId == "3")
        #expect(series.categoryIds == ["3", "4"])
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

    @Test
    func imagePrefetcherStoresFetchedDataInCache() async throws {
        let cache = URLCache(memoryCapacity: 5 * 1024 * 1024, diskCapacity: 5 * 1024 * 1024)
        let counter = InvocationCounter()
        let data = Data("poster-data".utf8)
        let url = URL(string: "https://img.example.com/poster-\(UUID().uuidString).jpg")!

        let prefetcher = URLSessionImagePrefetcher(
            cache: cache,
            maxAge: 600
        ) { requestedURL in
            await counter.increment()
            return (data, try makeResponse(url: requestedURL))
        }

        await prefetcher.prefetch(urls: [url])

        let cached = cache.cachedResponse(for: URLRequest(url: url))
        #expect(cached?.data == data)
        #expect(await counter.value == 1)
    }

    @Test
    func imagePrefetcherSkipsFetchWhenImageAlreadyCached() async throws {
        let cache = URLCache(memoryCapacity: 5 * 1024 * 1024, diskCapacity: 5 * 1024 * 1024)
        let counter = InvocationCounter()
        let data = Data("cached-poster".utf8)
        let url = URL(string: "https://img.example.com/already-cached-\(UUID().uuidString).jpg")!

        let response = try makeResponse(url: url)
        let cached = CachedURLResponse(response: response, data: data)
        cache.storeCachedResponse(cached, for: URLRequest(url: url))

        let prefetcher = URLSessionImagePrefetcher(cache: cache) { requestedURL in
            await counter.increment()
            return (Data(), try makeResponse(url: requestedURL))
        }

        await prefetcher.prefetch(urls: [url])

        #expect(await counter.value == 0)
        #expect(cache.cachedResponse(for: URLRequest(url: url))?.data == data)
    }

    @Test
    func imagePrefetcherDeduplicatesRepeatedURLsInSingleRequest() async throws {
        let cache = URLCache(memoryCapacity: 5 * 1024 * 1024, diskCapacity: 5 * 1024 * 1024)
        let counter = InvocationCounter()
        let url = URL(string: "https://img.example.com/repeated-\(UUID().uuidString).jpg")!

        let prefetcher = URLSessionImagePrefetcher(cache: cache) { requestedURL in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(75))
            return (Data("image".utf8), try makeResponse(url: requestedURL))
        }

        await prefetcher.prefetch(urls: [url, url, url])

        #expect(await counter.value == 1)
        #expect(cache.cachedResponse(for: URLRequest(url: url)) != nil)
    }

    @Test
    func avBackendCapabilityMappingRequiresDiscoveredVariantsForQualitySelection() {
        let backend = AVPlaybackBackend()
        let qualities = backend.qualityVariants()

        #expect(qualities.isEmpty)

        let caps = backend.capabilities()
        #expect(caps.supportsQualitySelection == false)
        #expect(caps.supportsAudioDelay == false)
    }

    @Test
    func vlcBackendCapabilityMappingReflectsRuntimeFeatureSet() {
        let backend = VLCPlaybackBackend()
        let caps = backend.capabilities()

        #expect(caps.supportsAudioTracks == false)
        #expect(caps.supportsSubtitles == false)
        #expect(caps.supportsQualitySelection == false)
        #expect(caps.supportsChapterMarkers == false)
        #expect(caps.supportsAudioDelay == true)
        #if os(iOS) || os(tvOS)
        #expect(caps.supportsOutputRouteSelection == true)
        #expect(caps.supportsBrightness == true)
        #else
        #expect(caps.supportsOutputRouteSelection == false)
        #expect(caps.supportsBrightness == false)
        #endif
    }

    @Test
    func playerMapsAdvancedCapabilitiesAndCollectionsFromBackend() async {
        let audio = [
            MediaTrack(id: "aud-en", kind: .audio, languageCode: "en", label: "English", isDefault: true, isForced: false),
            MediaTrack(id: "aud-es", kind: .audio, languageCode: "es", label: "Spanish", isDefault: false, isForced: false)
        ]
        let subtitles = [
            MediaTrack(id: "sub-en", kind: .subtitle, languageCode: "en", label: "English CC", isDefault: true, isForced: false)
        ]
        let qualities = [
            QualityVariant.auto,
            QualityVariant(id: "q-720", label: "720p", bitrate: 3_000_000, resolution: "1280x720", frameRate: 30, isAuto: false)
        ]
        let chapters = [
            ChapterMarker(id: "c2", title: "Second", startSeconds: 120),
            ChapterMarker(id: "c1", title: "First", startSeconds: 10)
        ]
        let routes = [
            OutputRoute(id: "route-a", name: "Built-in", isActive: true),
            OutputRoute(id: "route-b", name: "AirPlay", isActive: false)
        ]
        let caps = PlaybackCapabilities(
            supportsAudioTracks: true,
            supportsSubtitles: true,
            supportsQualitySelection: true,
            supportsChapterMarkers: true,
            supportsOutputRouteSelection: true,
            supportsAudioDelay: true,
            supportsBrightness: true
        )
        let backend = MockBackend(
            id: .vlc,
            canPlayResult: true,
            capabilities: caps,
            audioTracks: audio,
            subtitleTracks: subtitles,
            qualityVariants: qualities,
            chapterMarkers: chapters,
            outputRoutes: routes
        )
        let factory = PlaybackBackendFactory(builders: [{ backend }])
        let player = Player(backendFactory: factory)

        player.load(makeVideo(containerExtension: "mkv"), URL(string: "https://example.com/movie.mkv")!, presentation: .fullWindow, autoplay: false)
        backend.emit(.ready(duration: 300))
        _ = await waitUntil { player.duration == 300 }

        #expect(player.capabilities == caps)
        #expect(player.audioTracks == audio)
        #expect(player.subtitleTracks == subtitles)
        #expect(player.qualityVariants == qualities)
        #expect(player.chapterMarkers.map(\.id) == ["c1", "c2"])
        #expect(player.selectedOutputRouteID == "route-a")
    }

    @Test
    func qualitySelectionFailureRevertsToPreviousVariant() async {
        let qualities = [
            QualityVariant.auto,
            QualityVariant(id: "q-1080", label: "1080p", bitrate: 5_000_000, resolution: "1920x1080", frameRate: 30, isAuto: false)
        ]
        let caps = PlaybackCapabilities(
            supportsAudioTracks: false,
            supportsSubtitles: false,
            supportsQualitySelection: true,
            supportsChapterMarkers: false,
            supportsOutputRouteSelection: false,
            supportsAudioDelay: false,
            supportsBrightness: false
        )
        let backend = MockBackend(
            id: .vlc,
            canPlayResult: true,
            capabilities: caps,
            qualityVariants: qualities
        )
        backend.shouldFailQualitySelection = true
        let factory = PlaybackBackendFactory(builders: [{ backend }])
        let player = Player(backendFactory: factory)

        player.load(makeVideo(containerExtension: "mkv"), URL(string: "https://example.com/movie.mkv")!, presentation: .fullWindow, autoplay: false)
        backend.emit(.ready(duration: 120))
        _ = await waitUntil { player.duration == 120 }

        #expect(player.selectedQualityVariantID == QualityVariant.auto.id)
        player.selectQualityVariant(id: "q-1080")

        #expect(player.selectedQualityVariantID == QualityVariant.auto.id)
        #expect(player.controlMessage?.contains("Could not switch quality") == true)
        #expect(backend.selectedQualityVariantIDs.isEmpty)

        backend.shouldFailQualitySelection = false
        player.selectQualityVariant(id: "q-1080")
        #expect(player.selectedQualityVariantID == "q-1080")
        #expect(backend.selectedQualityVariantIDs == ["q-1080"])
    }

    @Test
    func trackAndSubtitleSelectionTransitionsPersistInPlayerState() async {
        let audio = [
            MediaTrack(id: "aud-en", kind: .audio, languageCode: "en", label: "English", isDefault: true, isForced: false),
            MediaTrack(id: "aud-es", kind: .audio, languageCode: "es", label: "Spanish", isDefault: false, isForced: false)
        ]
        let subtitles = [
            MediaTrack(id: "sub-en", kind: .subtitle, languageCode: "en", label: "English", isDefault: true, isForced: false),
            MediaTrack(id: "sub-es", kind: .subtitle, languageCode: "es", label: "Spanish", isDefault: false, isForced: false)
        ]
        let caps = PlaybackCapabilities(
            supportsAudioTracks: true,
            supportsSubtitles: true,
            supportsQualitySelection: false,
            supportsChapterMarkers: false,
            supportsOutputRouteSelection: false,
            supportsAudioDelay: false,
            supportsBrightness: false
        )
        let backend = MockBackend(
            id: .vlc,
            canPlayResult: true,
            capabilities: caps,
            audioTracks: audio,
            subtitleTracks: subtitles
        )
        let factory = PlaybackBackendFactory(builders: [{ backend }])
        let player = Player(backendFactory: factory)

        player.load(makeVideo(containerExtension: "mkv"), URL(string: "https://example.com/movie.mkv")!, presentation: .fullWindow, autoplay: false)
        backend.emit(.ready(duration: 120))
        _ = await waitUntil { player.duration == 120 }

        player.selectAudioTrack(id: "aud-es")
        player.selectSubtitleTrack(id: "sub-es")
        player.selectSubtitleTrack(id: MediaTrack.subtitleOffID)

        #expect(player.selectedAudioTrackID == "aud-es")
        #expect(player.selectedSubtitleTrackID == MediaTrack.subtitleOffID)
        #expect(backend.selectedAudioTrackIDs.last == "aud-es")
        #expect(backend.selectedSubtitleTrackIDs == ["sub-es", MediaTrack.subtitleOffID])
    }

    @Test
    func sleepTimerTracksDeadlineForDurationOptions() {
        let backend = MockBackend(id: .vlc, canPlayResult: true)
        let factory = PlaybackBackendFactory(builders: [{ backend }])
        let player = Player(backendFactory: factory)

        player.setSleepTimer(.minutes15)
        #expect(player.sleepTimerOption == .minutes15)
        #expect(player.sleepTimerEndsAt != nil)

        player.setSleepTimer(.off)
        #expect(player.sleepTimerOption == .off)
        #expect(player.sleepTimerEndsAt == nil)
    }

    @Test
    func preferencesAutoApplyWithLanguageFallback() async {
        let suiteName = "iptv.tests.player.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let keyPrefix = "player.preferences.profile-a"
        defaults.set(1.25, forKey: "\(keyPrefix).defaultSpeed")
        defaults.set(PlayerAspectRatioMode.fill.rawValue, forKey: "\(keyPrefix).defaultAspectRatio")
        defaults.set(120, forKey: "\(keyPrefix).defaultAudioDelayMs")
        defaults.set("es", forKey: "\(keyPrefix).preferredAudioLanguage")
        defaults.set("de", forKey: "\(keyPrefix).preferredSubtitleLanguage")
        defaults.set(true, forKey: "\(keyPrefix).defaultSubtitleEnabled")

        let audio = [
            MediaTrack(id: "aud-en", kind: .audio, languageCode: "en", label: "English", isDefault: true, isForced: false),
            MediaTrack(id: "aud-es", kind: .audio, languageCode: "es", label: "Spanish", isDefault: false, isForced: false)
        ]
        let subtitles = [
            MediaTrack(id: "sub-fr", kind: .subtitle, languageCode: "fr", label: "French", isDefault: true, isForced: false)
        ]
        let caps = PlaybackCapabilities(
            supportsAudioTracks: true,
            supportsSubtitles: true,
            supportsQualitySelection: false,
            supportsChapterMarkers: false,
            supportsOutputRouteSelection: false,
            supportsAudioDelay: true,
            supportsBrightness: false
        )
        let backend = MockBackend(
            id: .vlc,
            canPlayResult: true,
            capabilities: caps,
            audioTracks: audio,
            subtitleTracks: subtitles
        )
        let factory = PlaybackBackendFactory(builders: [{ backend }])
        let player = Player(
            backendFactory: factory,
            providerFingerprintProvider: { "profile-a" },
            defaults: defaults
        )

        player.load(makeVideo(containerExtension: "mkv"), URL(string: "https://example.com/movie.mkv")!, presentation: .fullWindow, autoplay: false)
        backend.emit(.ready(duration: 120))
        _ = await waitUntil { player.duration == 120 }

        #expect(player.playbackSpeed == 1.25)
        #expect(player.aspectRatioMode == .fill)
        #expect(player.audioDelayMilliseconds == 120)
        #expect(player.selectedAudioTrackID == "aud-es")
        #expect(player.selectedSubtitleTrackID == "sub-fr")
        #expect(backend.playbackSpeedValues.contains(1.25))
        #expect(backend.aspectRatioValues.contains(.fill))
        #expect(backend.audioDelayValues.contains(120))
    }

    @Test
    func episodeQuickSwitchFailureExposesRetryAction() async {
        let backend = MockBackend(id: .vlc, canPlayResult: true)
        let factory = PlaybackBackendFactory(builders: [{ backend }])
        let player = Player(backendFactory: factory)

        let episode1 = Video(id: 2001, name: "Episode 1", containerExtension: "mp4", contentType: XtreamContentType.series.rawValue, coverImageURL: nil, tmdbId: nil, rating: nil)
        let episode2 = Video(id: 2002, name: "Episode 2", containerExtension: "mp4", contentType: XtreamContentType.series.rawValue, coverImageURL: nil, tmdbId: nil, rating: nil)

        player.load(episode1, URL(string: "https://example.com/episode1.mp4")!, presentation: .fullWindow, autoplay: false)
        var shouldFail = true
        player.configureEpisodeSwitcher(episodes: [episode1, episode2]) { episode in
            if shouldFail && episode.id == episode2.id {
                throw MockError.failed
            }
            return URL(string: "https://example.com/\(episode.id).mp4")!
        }

        player.quickSwitchEpisode(id: episode2.id)
        #expect(player.currentItem?.id == episode1.id)
        #expect(player.canRetryEpisodeSwitch)
        #expect(player.controlMessage?.contains("Could not switch episode") == true)

        shouldFail = false
        player.retryEpisodeSwitch()
        let switched = await waitUntil { player.currentItem?.id == episode2.id }
        #expect(switched)
        #expect(player.canRetryEpisodeSwitch == false)
    }

    @Test
    func outputRouteSelectionUpdatesSelectedRoute() async {
        let routes = [
            OutputRoute(id: "local", name: "Local", isActive: true),
            OutputRoute(id: "airplay", name: "AirPlay", isActive: false)
        ]
        let caps = PlaybackCapabilities(
            supportsAudioTracks: false,
            supportsSubtitles: false,
            supportsQualitySelection: false,
            supportsChapterMarkers: false,
            supportsOutputRouteSelection: true,
            supportsAudioDelay: false,
            supportsBrightness: false
        )
        let backend = MockBackend(
            id: .vlc,
            canPlayResult: true,
            capabilities: caps,
            outputRoutes: routes
        )
        let factory = PlaybackBackendFactory(builders: [{ backend }])
        let player = Player(backendFactory: factory)

        player.load(makeVideo(containerExtension: "mkv"), URL(string: "https://example.com/movie.mkv")!, presentation: .fullWindow, autoplay: false)
        backend.emit(.ready(duration: 120))
        _ = await waitUntil { player.duration == 120 }

        #expect(player.selectedOutputRouteID == "local")
        player.selectOutputRoute(id: "airplay")

        #expect(player.selectedOutputRouteID == "airplay")
        #expect(player.outputRoutes.first(where: { $0.id == "airplay" })?.isActive == true)
        #expect(backend.selectedOutputRouteIDs == ["airplay"])
    }

    @Test
    func outputRouteRefreshPullsLatestBackendState() async {
        let routes = [
            OutputRoute(id: "local", name: "Local", isActive: true),
            OutputRoute(id: "airplay", name: "AirPlay", isActive: false)
        ]
        let caps = PlaybackCapabilities(
            supportsAudioTracks: false,
            supportsSubtitles: false,
            supportsQualitySelection: false,
            supportsChapterMarkers: false,
            supportsOutputRouteSelection: true,
            supportsAudioDelay: false,
            supportsBrightness: false
        )
        let backend = MockBackend(
            id: .vlc,
            canPlayResult: true,
            capabilities: caps,
            outputRoutes: routes
        )
        let factory = PlaybackBackendFactory(builders: [{ backend }])
        let player = Player(backendFactory: factory)

        player.load(makeVideo(containerExtension: "mkv"), URL(string: "https://example.com/movie.mkv")!, presentation: .fullWindow, autoplay: false)
        backend.emit(.ready(duration: 120))
        _ = await waitUntil { player.duration == 120 }

        #expect(player.selectedOutputRouteID == "local")

        backend.setOutputRoutes([
            OutputRoute(id: "local", name: "Local", isActive: false),
            OutputRoute(id: "airplay", name: "AirPlay", isActive: true)
        ])
        player.refreshOutputRoutes()

        #expect(player.selectedOutputRouteID == "airplay")
        #expect(player.outputRoutes.first(where: { $0.id == "airplay" })?.isActive == true)
    }

    @Test
    func outputRouteSelectionFallsBackWhenBackendReturnsNoRoutes() async {
        let routes = [
            OutputRoute(id: "local", name: "Local", isActive: true),
            OutputRoute(id: "airplay", name: "AirPlay", isActive: false)
        ]
        let caps = PlaybackCapabilities(
            supportsAudioTracks: false,
            supportsSubtitles: false,
            supportsQualitySelection: false,
            supportsChapterMarkers: false,
            supportsOutputRouteSelection: true,
            supportsAudioDelay: false,
            supportsBrightness: false
        )
        let backend = MockBackend(
            id: .vlc,
            canPlayResult: true,
            capabilities: caps,
            outputRoutes: routes
        )
        backend.clearOutputRoutesOnSelect = true
        let factory = PlaybackBackendFactory(builders: [{ backend }])
        let player = Player(backendFactory: factory)

        player.load(makeVideo(containerExtension: "mkv"), URL(string: "https://example.com/movie.mkv")!, presentation: .fullWindow, autoplay: false)
        backend.emit(.ready(duration: 120))
        _ = await waitUntil { player.duration == 120 }

        #expect(player.selectedOutputRouteID == "local")

        player.selectOutputRoute(id: "airplay")

        #expect(player.selectedOutputRouteID == "airplay")
        #expect(player.outputRoutes.count == 2)
        #expect(player.outputRoutes.first(where: { $0.id == "airplay" })?.isActive == true)
        #expect(player.outputRoutes.first(where: { $0.id == "local" })?.isActive == false)
        #expect(backend.selectedOutputRouteIDs == ["airplay"])
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
    private let mockedCapabilities: PlaybackCapabilities
    private let mockedAudioTracks: [MediaTrack]
    private let mockedSubtitleTracks: [MediaTrack]
    private let mockedQualityVariants: [QualityVariant]
    private let mockedChapterMarkers: [ChapterMarker]
    private var mockedOutputRoutes: [OutputRoute]

    private let stream: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    private(set) var loadCallCount = 0
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var toggleCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastSeekTime: Double?
    private(set) var selectedAudioTrackIDs: [String] = []
    private(set) var selectedSubtitleTrackIDs: [String] = []
    private(set) var selectedQualityVariantIDs: [String] = []
    private(set) var selectedOutputRouteIDs: [String] = []
    private(set) var playbackSpeedValues: [Double] = []
    private(set) var aspectRatioValues: [PlayerAspectRatioMode] = []
    private(set) var audioDelayValues: [Int] = []
    private(set) var volumeValues: [Double] = []
    private(set) var brightnessValues: [Double] = []
    var shouldFailQualitySelection = false
    var clearOutputRoutesOnSelect = false

    init(
        id: PlaybackBackendID,
        isAvailable: Bool = true,
        canPlayResult: Bool,
        capabilities: PlaybackCapabilities = .unsupported,
        audioTracks: [MediaTrack] = [],
        subtitleTracks: [MediaTrack] = [],
        qualityVariants: [QualityVariant] = [QualityVariant.auto],
        chapterMarkers: [ChapterMarker] = [],
        outputRoutes: [OutputRoute] = []
    ) {
        self.id = id
        self.isAvailable = isAvailable
        self.canPlayResult = canPlayResult
        self.mockedCapabilities = capabilities
        self.mockedAudioTracks = audioTracks
        self.mockedSubtitleTracks = subtitleTracks
        self.mockedQualityVariants = qualityVariants
        self.mockedChapterMarkers = chapterMarkers
        self.mockedOutputRoutes = outputRoutes

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

    func capabilities() -> PlaybackCapabilities {
        mockedCapabilities
    }

    func audioTracks() -> [MediaTrack] {
        mockedAudioTracks
    }

    func subtitleTracks() -> [MediaTrack] {
        mockedSubtitleTracks
    }

    func qualityVariants() -> [QualityVariant] {
        mockedQualityVariants
    }

    func chapterMarkers() -> [ChapterMarker] {
        mockedChapterMarkers
    }

    func availableOutputRoutes() -> [OutputRoute] {
        mockedOutputRoutes
    }

    func selectAudioTrack(id: String) {
        selectedAudioTrackIDs.append(id)
    }

    func selectSubtitleTrack(id: String) {
        selectedSubtitleTrackIDs.append(id)
    }

    func selectQualityVariant(id: String) throws {
        if shouldFailQualitySelection {
            throw MockError.failed
        }
        selectedQualityVariantIDs.append(id)
    }

    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeedValues.append(speed)
    }

    func setAspectRatio(_ mode: PlayerAspectRatioMode) {
        aspectRatioValues.append(mode)
    }

    func setAudioDelay(milliseconds: Int) {
        audioDelayValues.append(milliseconds)
    }

    func selectOutputRoute(id: String) {
        selectedOutputRouteIDs.append(id)
        if clearOutputRoutesOnSelect {
            mockedOutputRoutes = []
            return
        }

        if mockedOutputRoutes.contains(where: { $0.id == id }) {
            mockedOutputRoutes = mockedOutputRoutes.map { route in
                OutputRoute(id: route.id, name: route.name, isActive: route.id == id)
            }
        }
    }

    func setOutputRoutes(_ routes: [OutputRoute]) {
        mockedOutputRoutes = routes
    }

    func setVolume(_ value: Double) {
        volumeValues.append(value)
    }

    func setBrightness(_ value: Double) {
        brightnessValues.append(value)
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
        storage[key.rawKey]
    }

    func save(_ entry: StreamListCacheEntry, for key: StreamListCacheKey) async throws {
        storage[key.rawKey] = entry
    }

    func entries(providerFingerprint: String) async throws -> [StreamListCacheEntry] {
        storage.values.filter { $0.key.providerFingerprint == providerFingerprint }
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

private func makeResponse(url: URL) throws -> HTTPURLResponse {
    guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else {
        throw URLError(.badServerResponse)
    }
    return response
}
