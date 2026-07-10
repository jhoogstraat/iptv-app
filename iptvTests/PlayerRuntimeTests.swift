import Foundation
import SQLiteData
import Testing

@testable import iptv

@MainActor
@Suite("Player runtime", .serialized)
struct PlayerRuntimeTests {
    @Test func avBackendAcceptsExtensionlessHTTPStreamsAndRejectsUnsupportedSchemes() throws {
        let backend = AVPlaybackBackend(audioSessionCoordinator: RuntimeAudioSessionCoordinator())

        #expect(backend.canPlay(url: try #require(URL(string: "https://stream.example.com/movie/user/pass/42"))))
        #expect(backend.canPlay(url: try #require(URL(string: "http://stream.example.com/live/user/pass/7"))))
        #expect(backend.canPlay(url: try #require(URL(string: "https://stream.example.com/video.mp4"))))
        #expect(!backend.canPlay(url: try #require(URL(string: "ftp://stream.example.com/video.mp4"))))
        #expect(!backend.canPlay(url: try #require(URL(string: "rtsp://stream.example.com/live"))))
        #expect(!backend.canPlay(url: try #require(URL(string: "https://stream.example.com/video.exe"))))
    }

    @Test func vlcFallbackCarriesPositionAndPausedIntentWithoutRegressingAndOnlyRunsOnce() async throws {
        try await withRuntimeDatabase { database, credentials in
            let vlc = RuntimePlaybackBackend(id: .vlc)
            let av = RuntimePlaybackBackend(id: .av)
            let player = Player(
                backendFactory: PlaybackBackendFactory(builders: [{ vlc }, { av }]),
                database: database,
                playbackSourceResolver: RuntimePlaybackSourceResolver(),
                credentialStore: credentials
            )
            let media = makeMedia(sourceID: 101)

            player.load(media, presentation: .inline, autoplay: true)
            await Task.yield()
            vlc.send(.ready(duration: 600))
            vlc.send(.progress(currentTime: 75, duration: 600))
            try await eventually { player.currentTime == 75 }
            player.pause()
            vlc.send(.failed(RuntimePlaybackError.failed))

            try await eventually { av.loadedAutoplay == [false] }
            av.send(.ready(duration: 600))
            try await eventually { av.seekTimes == [75] }
            av.send(.progress(currentTime: 0, duration: 600))
            await Task.yield()

            #expect(player.currentTime == 75)
            #expect(!player.isPlaying)

            av.send(.failed(RuntimePlaybackError.failed))
            try await eventually {
                if case .failed = player.playbackState { return true }
                return false
            }
            #expect(vlc.loadedAutoplay.count == 1)
            #expect(av.loadedAutoplay.count == 1)
            await player.closeAndFlush()
        }
    }

    @Test func replaySeeksToZeroBeforeStartingPlaybackAndBeginsANewWatchOrdering() async throws {
        try await withRuntimeDatabase { database, credentials in
            let backend = RuntimePlaybackBackend(id: .av)
            let player = Player(
                backendFactory: PlaybackBackendFactory(builders: [{ backend }]),
                database: database,
                playbackSourceResolver: RuntimePlaybackSourceResolver(),
                credentialStore: credentials
            )

            player.load(makeMedia(sourceID: 102), presentation: .inline)
            await Task.yield()
            backend.send(.ready(duration: 300))
            backend.send(.progress(currentTime: 299, duration: 300))
            backend.send(.ended)
            try await eventually { player.isPlaybackComplete }
            backend.operations.removeAll()

            player.play()

            #expect(backend.operations == [.seek(0), .play])
            #expect(player.currentTime == 0)
            #expect(!player.isPlaybackComplete)
            await player.closeAndFlush()
        }
    }

    @Test func delayedTrackMetadataAppliesOnlyNormalizedLanguageMatchAndSubtitleOff() async throws {
        try await withRuntimeDatabase { database, credentials in
            let defaultsName = "PlayerRuntimeTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: defaultsName))
            defer { defaults.removePersistentDomain(forName: defaultsName) }
            defaults.set("de_DE", forKey: "preferredAudioLanguage")
            defaults.set(false, forKey: "defaultSubtitleEnabled")

            let backend = RuntimePlaybackBackend(id: .av)
            let player = Player(
                backendFactory: PlaybackBackendFactory(builders: [{ backend }]),
                database: database,
                playbackSourceResolver: RuntimePlaybackSourceResolver(),
                credentialStore: credentials,
                defaults: defaults
            )

            player.load(makeMedia(sourceID: 103), presentation: .inline)
            await Task.yield()
            backend.send(.ready(duration: 600))
            await Task.yield()
            #expect(backend.selectedAudioTrackIDs.isEmpty)
            #expect(backend.selectedSubtitleTrackIDs.isEmpty)

            backend.currentAudioTracks = [
                MediaTrack(id: "english", kind: .audio, languageCode: "en-US", label: "English", isDefault: true, isForced: false),
                MediaTrack(id: "german", kind: .audio, languageCode: "de-de", label: "Deutsch", isDefault: false, isForced: false),
            ]
            backend.currentSubtitleTracks = [
                MediaTrack(id: "english-subs", kind: .subtitle, languageCode: "en_US", label: "English", isDefault: true, isForced: false),
            ]
            backend.send(.advancedStateChanged)
            try await eventually {
                backend.selectedAudioTrackIDs == ["german"]
                    && backend.selectedSubtitleTrackIDs == [MediaTrack.subtitleOffID]
            }

            #expect(player.selectedAudioTrackID == "german")
            #expect(player.selectedSubtitleTrackID == MediaTrack.subtitleOffID)
            await player.closeAndFlush()
        }
    }

    @Test func livePlaybackRejectsSeekAndRateChangesAtPlayerBoundary() async throws {
        try await withRuntimeDatabase { database, credentials in
            let backend = RuntimePlaybackBackend(id: .av)
            let player = Player(
                backendFactory: PlaybackBackendFactory(builders: [{ backend }]),
                database: database,
                playbackSourceResolver: RuntimePlaybackSourceResolver(),
                credentialStore: credentials
            )

            player.load(makeMedia(sourceID: 104, type: .live), presentation: .inline)
            await Task.yield()
            backend.send(.ready(duration: nil))
            try await eventually { !backend.playbackSpeeds.isEmpty }
            let speedCallCount = backend.playbackSpeeds.count

            player.seek(to: 120)
            player.setPlaybackSpeed(1.5)

            #expect(backend.seekTimes.isEmpty)
            #expect(backend.playbackSpeeds.count == speedCallCount)
            #expect(player.playbackSpeed == 1)
            #expect(player.controlMessage == "Playback speed is unavailable for live channels.")
            await player.closeAndFlush()
        }
    }

    @Test func closeAndFlushMakesForcedProgressImmediatelyObservable() async throws {
        try await withRuntimeDatabase { database, credentials in
            let backend = RuntimePlaybackBackend(id: .av)
            let player = Player(
                backendFactory: PlaybackBackendFactory(builders: [{ backend }]),
                database: database,
                playbackSourceResolver: RuntimePlaybackSourceResolver(),
                credentialStore: credentials
            )
            let media = makeMedia(sourceID: 105)
            let storedProviderID = try activeProviderID(database: database)
            let providerID = try #require(storedProviderID)

            player.load(media, presentation: .inline)
            await Task.yield()
            backend.send(.ready(duration: 600))
            backend.send(.progress(currentTime: 87, duration: 600))
            try await eventually { player.currentTime == 87 }

            await player.closeAndFlush()

            let activity = try #require(
                WatchActivityStore.activity(for: media, providerID: providerID, database: database)
            )
            #expect(activity.currentTime == 87)
            #expect(!activity.completed)
        }
    }

    @Test func avAudioSessionActivationIsInjectedIdempotentAndDeactivatedOnStop() throws {
        let audioSession = RuntimeAudioSessionCoordinator()
        let backend = AVPlaybackBackend(audioSessionCoordinator: audioSession)
        let firstURL = try #require(URL(string: "https://stream.example.com/movie/user/pass/1"))
        let secondURL = try #require(URL(string: "https://stream.example.com/movie/user/pass/2"))

        try backend.load(url: firstURL, autoplay: false)
        try backend.load(url: secondURL, autoplay: false)
        #expect(audioSession.activationCount == 1)
        #expect(audioSession.deactivationCount == 0)

        backend.stop()
        backend.stop()
        #expect(audioSession.activationCount == 1)
        #expect(audioSession.deactivationCount == 1)
    }

    private func withRuntimeDatabase<T>(
        _ operation: (any DatabaseWriter, TestProviderCredentialStore) async throws -> T
    ) async throws -> T {
        let credentials = TestProviderCredentialStore(passwords: ["runtime-credential": "pass"])
        let database = try testAppDatabase(credentialStore: credentials)
        try resetDatabase(database)
        try insertProvider(database: database)
        return try await operation(database, credentials)
    }

    private func resetDatabase(_ database: any DatabaseWriter) throws {
        try database.write { db in
            try WatchActivity.delete().execute(db)
            try SeriesSeason.delete().execute(db)
            try Media.delete().execute(db)
            try Category.delete().execute(db)
            try Provider.delete().execute(db)
        }
    }

    private func insertProvider(database: any DatabaseWriter) throws {
        try database.write { db in
            try Provider.insert {
                Provider.Draft(
                    id: nil,
                    kind: .xtream,
                    name: "Runtime Provider",
                    username: "user",
                    credentialReference: "runtime-credential",
                    endpoint: URL(string: "https://stream.example.com")!,
                    allowsInsecureHTTP: false,
                    isInitialized: true,
                    isActive: true
                )
            }.execute(db)
        }
    }

    private func activeProviderID(database: any DatabaseReader) throws -> Provider.ID? {
        try database.read { db in
            try Provider.where(\.isActive).select(\.id).fetchOne(db)
        }
    }

    private func makeMedia(sourceID: Int, type: MediaType = .movie) -> Media {
        Media(
            id: sourceID,
            sourceID: sourceID,
            type: type,
            title: "Runtime item \(sourceID)",
            categoryID: nil,
            tmdbID: nil,
            coverURL: nil,
            rating: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func eventually(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<80 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(predicate())
    }
}

private enum RuntimePlaybackError: Error {
    case failed
}

private struct RuntimePlaybackSourceResolver: MediaPlaybackSourceResolving {
    func playbackURL(for media: Media, provider: Provider) throws -> URL {
        try #require(URL(string: "https://stream.example.com/play/\(media.sourceID)"))
    }
}

@MainActor
private final class RuntimeAudioSessionCoordinator: PlaybackAudioSessionCoordinating {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0

    func activatePlayback() throws {
        activationCount += 1
    }

    func deactivatePlayback() {
        deactivationCount += 1
    }
}

@MainActor
private final class RuntimePlaybackBackend: PlaybackBackend {
    enum Operation: Equatable {
        case play
        case pause
        case seek(Double)
    }

    let id: PlaybackBackendID
    let isAvailable = true
    private let eventStream: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    var currentAudioTracks: [MediaTrack] = []
    var currentSubtitleTracks: [MediaTrack] = []
    var currentQualityVariants: [QualityVariant] = []
    private(set) var loadedAutoplay: [Bool] = []
    private(set) var seekTimes: [Double] = []
    private(set) var playbackSpeeds: [Double] = []
    private(set) var selectedAudioTrackIDs: [String] = []
    private(set) var selectedSubtitleTrackIDs: [String] = []
    var operations: [Operation] = []

    init(id: PlaybackBackendID) {
        self.id = id
        var continuation: AsyncStream<PlaybackEvent>.Continuation?
        eventStream = AsyncStream { continuation = $0 }
        self.continuation = continuation!
    }

    func canPlay(url: URL) -> Bool { true }

    func load(url: URL, autoplay: Bool) throws {
        loadedAutoplay.append(autoplay)
    }

    func play() {
        operations.append(.play)
    }

    func pause() {
        operations.append(.pause)
    }

    func togglePlayback() {}
    func stop() {}

    func seek(to seconds: Double) {
        seekTimes.append(seconds)
        operations.append(.seek(seconds))
    }

    func events() -> AsyncStream<PlaybackEvent> {
        eventStream
    }

    func capabilities() -> PlaybackCapabilities {
        PlaybackCapabilities(
            supportsAudioTracks: !currentAudioTracks.isEmpty,
            supportsSubtitles: !currentSubtitleTracks.isEmpty,
            supportsQualitySelection: currentQualityVariants.count > 1,
            supportsChapterMarkers: false,
            supportsOutputRouteSelection: false,
            supportsAudioDelay: false,
            supportsBrightness: false
        )
    }

    func audioTracks() -> [MediaTrack] { currentAudioTracks }
    func subtitleTracks() -> [MediaTrack] { currentSubtitleTracks }
    func qualityVariants() -> [QualityVariant] { currentQualityVariants }

    func selectAudioTrack(id: String) {
        selectedAudioTrackIDs.append(id)
    }

    func selectSubtitleTrack(id: String) {
        selectedSubtitleTrackIDs.append(id)
    }

    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeeds.append(speed)
    }

    func send(_ event: PlaybackEvent) {
        continuation.yield(event)
    }
}
