import Foundation
import SQLiteData
import Testing

@testable import iptv

@MainActor
@Suite("Watch activity", .serialized)
struct WatchActivityStoreTests {
    @Test func recordProgressUpsertsProviderScopedSnapshotAndResumeSurvivesFreshRead() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let firstProviderID = try insertProvider(name: "Primary", isActive: true, database: database)
            let secondProviderID = try insertProvider(name: "Secondary", isActive: false, database: database)
            let categoryID = try insertCategory(title: "Movies", database: database)
            let media = makeMedia(sourceID: 700, title: "Resume Me", categoryID: categoryID)

            _ = await WatchActivityStore.recordProgress(
                for: media,
                providerID: firstProviderID,
                currentTime: 95,
                duration: 600,
                completed: false,
                writeStamp: stamp(session: 100, generation: 1),
                database: database
            )
            _ = await WatchActivityStore.recordProgress(
                for: media,
                providerID: secondProviderID,
                currentTime: 45,
                duration: 500,
                completed: false,
                writeStamp: stamp(session: 100, generation: 1),
                database: database
            )
            _ = await WatchActivityStore.recordProgress(
                for: media,
                providerID: firstProviderID,
                currentTime: 125,
                duration: 600,
                completed: false,
                writeStamp: stamp(session: 100, generation: 2),
                database: database
            )

            let activity = try #require(WatchActivityStore.activity(for: media, providerID: firstProviderID, database: database))
            let otherProviderActivity = try #require(WatchActivityStore.activity(for: media, providerID: secondProviderID, database: database))

            #expect(activity.currentTime == 125)
            #expect(activity.duration == 600)
            #expect(activity.completed == false)
            #expect(activity.title == "Resume Me")
            #expect(activity.artworkURL == media.backdropURL)
            #expect(activity.categoryTitle == "Movies")
            #expect(activity.isResumeEligible)
            #expect(WatchActivityStore.resumeTime(for: media, providerID: firstProviderID, database: database) == 125)
            #expect(otherProviderActivity.currentTime == 45)
        }
    }

    @Test func unfinishedActivitiesExcludeCompletedAndIneligibleRowsSortedByLastWatched() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            let old = Date(timeIntervalSince1970: 100)
            let newest = Date(timeIntervalSince1970: 300)
            let middle = Date(timeIntervalSince1970: 200)

            try database.write { db in
                try WatchActivity.insert {
                    WatchActivity.Draft(
                        id: nil,
                        profileID: UserProfileStore.primaryProfileID,
                        providerID: providerID,
                        mediaType: .movie,
                        sourceID: 1,
                        title: "Old Eligible",
                        artworkURL: nil,
                        categoryTitle: nil,
                        currentTime: 60,
                        duration: 600,
                        completed: false,
                        lastWatchedAt: old,
                        updatedAt: old
                    )
                }.execute(db)
                try WatchActivity.insert {
                    WatchActivity.Draft(
                        id: nil,
                        profileID: UserProfileStore.primaryProfileID,
                        providerID: providerID,
                        mediaType: .episode,
                        sourceID: 2,
                        title: "Newest Eligible",
                        artworkURL: nil,
                        categoryTitle: nil,
                        currentTime: 120,
                        duration: 900,
                        completed: false,
                        lastWatchedAt: newest,
                        updatedAt: newest
                    )
                }.execute(db)
                try WatchActivity.insert {
                    WatchActivity.Draft(
                        id: nil,
                        profileID: UserProfileStore.primaryProfileID,
                        providerID: providerID,
                        mediaType: .movie,
                        sourceID: 3,
                        title: "Too Short",
                        artworkURL: nil,
                        categoryTitle: nil,
                        currentTime: 12,
                        duration: 600,
                        completed: false,
                        lastWatchedAt: middle,
                        updatedAt: middle
                    )
                }.execute(db)
                try WatchActivity.insert {
                    WatchActivity.Draft(
                        id: nil,
                        profileID: UserProfileStore.primaryProfileID,
                        providerID: providerID,
                        mediaType: .movie,
                        sourceID: 4,
                        title: "Completed",
                        artworkURL: nil,
                        categoryTitle: nil,
                        currentTime: 600,
                        duration: 600,
                        completed: true,
                        lastWatchedAt: Date(timeIntervalSince1970: 400),
                        updatedAt: Date(timeIntervalSince1970: 400)
                    )
                }.execute(db)
            }

            let unfinished = WatchActivityStore.unfinishedActivities(for: providerID, database: database)

            #expect(unfinished.map(\.sourceID) == [2, 1])
        }
    }

    @Test func activityOrderingUsesMediaTypeSourceAndLocalIDTieBreakers() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            let watchedAt = Date(timeIntervalSince1970: 500)

            try database.write { db in
                try WatchActivity.insert {
                    WatchActivity.Draft(
                        id: nil,
                        profileID: UserProfileStore.primaryProfileID,
                        providerID: providerID,
                        mediaType: .episode,
                        sourceID: 44,
                        title: "Same",
                        artworkURL: nil,
                        categoryTitle: nil,
                        currentTime: 90,
                        duration: 600,
                        completed: false,
                        lastWatchedAt: watchedAt,
                        updatedAt: watchedAt
                    )
                }.execute(db)
                try WatchActivity.insert {
                    WatchActivity.Draft(
                        id: nil,
                        profileID: UserProfileStore.primaryProfileID,
                        providerID: providerID,
                        mediaType: .movie,
                        sourceID: 44,
                        title: "Same",
                        artworkURL: nil,
                        categoryTitle: nil,
                        currentTime: 90,
                        duration: 600,
                        completed: false,
                        lastWatchedAt: watchedAt,
                        updatedAt: watchedAt
                    )
                }.execute(db)
            }

            let ordered = WatchActivityStore.unfinishedActivities(for: providerID, database: database)
            #expect(ordered.map(\.mediaType) == [.movie, .episode])

            let lowerID = WatchActivity(
                id: 1,
                profileID: UserProfileStore.primaryProfileID,
                providerID: providerID,
                mediaType: .movie,
                sourceID: 44,
                title: "Same",
                artworkURL: nil,
                categoryTitle: nil,
                currentTime: 90,
                duration: 600,
                completed: false,
                lastWatchedAt: watchedAt,
                updatedAt: watchedAt
            )
            let higherID = WatchActivity(
                id: 2,
                profileID: UserProfileStore.primaryProfileID,
                providerID: providerID,
                mediaType: .movie,
                sourceID: 44,
                title: "Same",
                artworkURL: nil,
                categoryTitle: nil,
                currentTime: 90,
                duration: 600,
                completed: false,
                lastWatchedAt: watchedAt,
                updatedAt: watchedAt
            )
            #expect(WatchActivityStore.activityOrdering(lowerID, higherID))
            #expect(WatchActivityStore.activityOrdering(higherID, lowerID) == false)
        }
    }

    @Test func reversedStaleWriteCannotOverwriteNewerPlaybackSnapshot() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            let media = makeMedia(sourceID: 704, title: "Ordered")
            let sessionStartedAt = Date(timeIntervalSince1970: 600)

            let committedNewer = await WatchActivityStore.recordProgress(
                for: media,
                providerID: providerID,
                currentTime: 600,
                duration: 600,
                completed: true,
                writeStamp: .init(sessionStartedAt: sessionStartedAt, generation: 2),
                database: database
            )
            let rejectedOlder = await WatchActivityStore.recordProgress(
                for: media,
                providerID: providerID,
                currentTime: 90,
                duration: 600,
                completed: false,
                writeStamp: .init(sessionStartedAt: sessionStartedAt, generation: 1),
                database: database
            )

            #expect(committedNewer)
            #expect(rejectedOlder == false)
            let activity = try #require(
                WatchActivityStore.activity(for: media, providerID: providerID, database: database)
            )
            #expect(activity.currentTime == 600)
            #expect(activity.completed)
            #expect(activity.writeSessionStartedAt == sessionStartedAt)
            #expect(activity.writeGeneration == 2)
        }
    }

    @Test func laterRewatchSessionCanReplaceCompletedActivityWithLowerGeneration() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            let media = makeMedia(sourceID: 705, title: "Rewatch")

            let completed = await WatchActivityStore.recordProgress(
                for: media,
                providerID: providerID,
                currentTime: 600,
                duration: 600,
                completed: true,
                writeStamp: stamp(session: 700, generation: 8),
                database: database
            )
            let rewatched = await WatchActivityStore.recordProgress(
                for: media,
                providerID: providerID,
                currentTime: 75,
                duration: 600,
                completed: false,
                writeStamp: stamp(session: 800, generation: 1),
                database: database
            )

            #expect(completed)
            #expect(rewatched)
            let activity = try #require(
                WatchActivityStore.activity(for: media, providerID: providerID, database: database)
            )
            #expect(activity.currentTime == 75)
            #expect(activity.completed == false)
            #expect(activity.isResumeEligible)
            #expect(activity.writeSessionStartedAt == Date(timeIntervalSince1970: 800))
            #expect(activity.writeGeneration == 1)
        }
    }

    @Test func explicitProviderDeleteClearsWatchActivity() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            let media = makeMedia(sourceID: 88, title: "Tracked")
            _ = await WatchActivityStore.recordProgress(
                for: media,
                providerID: providerID,
                currentTime: 80,
                duration: 600,
                completed: false,
                writeStamp: stamp(session: 900, generation: 1),
                database: database
            )
            #expect(WatchActivityStore.activity(for: media, providerID: providerID, database: database) != nil)

            let credentialStore = TestProviderCredentialStore(passwords: ["test-Primary": "pass"])
            let manager = ProviderManager(database: database, credentialStore: credentialStore)
            try manager.loadActive()
            try manager.delete(provider: providerID)

            #expect(WatchActivityStore.activity(for: media, providerID: providerID, database: database) == nil)
        }
    }

    @Test func playerRecordsProgressAndSeeksToEligibleStoredResumePoint() async throws {
        try await withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            let media = makeMedia(sourceID: 901, title: "Playable")
            let backend = FakePlaybackBackend()
            let credentials = TestProviderCredentialStore(passwords: ["test-Primary": "pass"])
            let player = Player(
                backendFactory: PlaybackBackendFactory(builders: [{ backend }]),
                database: database,
                playbackSourceResolver: StubPlaybackSourceResolver(),
                credentialStore: credentials
            )

            player.load(media, presentation: .inline)
            await Task.yield()
            backend.send(.ready(duration: 600))
            backend.send(.progress(currentTime: 75, duration: 600))

            let recorded = try await eventuallyActivity(for: media, providerID: providerID, database: database)
            #expect(recorded.currentTime == 75)
            #expect(recorded.duration == 600)
            #expect(recorded.completed == false)

            player.reset()
            _ = await WatchActivityStore.recordProgress(
                for: media,
                providerID: providerID,
                currentTime: 140,
                duration: 600,
                completed: false,
                writeStamp: stamp(session: Date().addingTimeInterval(1).timeIntervalSince1970, generation: 1),
                database: database
            )

            let resumeBackend = FakePlaybackBackend()
            let resumePlayer = Player(
                backendFactory: PlaybackBackendFactory(builders: [{ resumeBackend }]),
                database: database,
                playbackSourceResolver: StubPlaybackSourceResolver(),
                credentialStore: credentials
            )

            resumePlayer.load(media, presentation: .inline)
            await Task.yield()
            resumeBackend.send(.ready(duration: 600))
            try await eventually { resumeBackend.seekTimes.contains(140) }

            #expect(resumePlayer.currentTime == 140)
        }
    }

    @Test func resumePolicyRejectsCompletedAndTooShortProgress() {
        #expect(WatchActivityStore.isResumeEligible(currentTime: 29, duration: 600, completed: false) == false)
        #expect(WatchActivityStore.isResumeEligible(currentTime: 60, duration: 600, completed: true) == false)
        #expect(WatchActivityStore.isResumeEligible(currentTime: 580, duration: 600, completed: false) == false)
        #expect(WatchActivityStore.isResumeEligible(currentTime: 120, duration: 600, completed: false))
    }

    private func withTestDatabase<T>(_ operation: (any DatabaseWriter) throws -> T) throws -> T {
        let database = try testAppDatabase(credentialStore: TestProviderCredentialStore())
        return try operation(database)
    }

    private func withTestDatabase<T>(_ operation: (any DatabaseWriter) async throws -> T) async throws -> T {
        let database = try testAppDatabase(credentialStore: TestProviderCredentialStore())
        return try await operation(database)
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

    @discardableResult
    private func insertProvider(name: String, isActive: Bool, database: any DatabaseWriter) throws -> Provider.ID {
        let endpoint = try #require(URL(string: "https://example.com"))
        var providerID: Provider.ID?
        try database.write { db in
            let provider = try Provider.insert {
                Provider.Draft(
                    id: nil,
                    kind: .xtream,
                    name: name,
                    username: "user",
                    credentialReference: "test-\(name)",
                    endpoint: endpoint,
                    allowsInsecureHTTP: false,
                    isActive: isActive
                )
            }
            .returning(\.self)
            .fetchOne(db)!
            providerID = provider.id
        }
        return try #require(providerID)
    }

    @discardableResult
    private func insertCategory(title: String, database: any DatabaseWriter) throws -> iptv.Category.ID {
        var categoryID: iptv.Category.ID?
        try database.write { db in
            let category = try iptv.Category.insert {
                iptv.Category.Draft(id: nil, sourceID: title, type: .movie, title: title, updatedAt: Date())
            }
            .returning(\.self)
            .fetchOne(db)!
            categoryID = category.id
        }
        return try #require(categoryID)
    }

    private func makeMedia(sourceID: Int, title: String, categoryID: iptv.Category.ID? = nil) -> Media {
        Media(
            id: sourceID,
            sourceID: sourceID,
            type: .movie,
            title: title,
            categoryID: categoryID,
            tmdbID: nil,
            coverURL: URL(string: "https://img.example.com/poster.jpg"),
            rating: nil,
            backdropURL: URL(string: "https://img.example.com/backdrop.jpg"),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func stamp(session: TimeInterval, generation: UInt64) -> WatchActivityStore.WriteStamp {
        WatchActivityStore.WriteStamp(
            sessionStartedAt: Date(timeIntervalSince1970: session),
            generation: generation
        )
    }

    private func eventuallyActivity(
        for media: Media,
        providerID: Provider.ID,
        database: any DatabaseWriter
    ) async throws -> WatchActivity {
        var lastActivity: WatchActivity?
        for _ in 0..<40 {
            if let activity = WatchActivityStore.activity(for: media, providerID: providerID, database: database) {
                return activity
            }
            try await Task.sleep(for: .milliseconds(25))
            lastActivity = WatchActivityStore.activity(for: media, providerID: providerID, database: database)
        }
        return try #require(lastActivity)
    }

    private func eventually(_ predicate: @escaping () -> Bool) async throws {
        for _ in 0..<40 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(predicate())
    }
}

private struct StubPlaybackSourceResolver: MediaPlaybackSourceResolving {
    func playbackURL(for media: Media, provider: Provider) throws -> URL {
        try #require(URL(string: "https://stream.example.com/movie/user/pass/\(media.sourceID).mp4"))
    }
}

private final class FakePlaybackBackend: PlaybackBackend {
    let id: PlaybackBackendID = .av
    let isAvailable = true
    private let eventStream: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private(set) var loadedURL: URL?
    private(set) var seekTimes: [Double] = []

    init() {
        var continuation: AsyncStream<PlaybackEvent>.Continuation?
        eventStream = AsyncStream { continuation = $0 }
        self.continuation = continuation!
    }

    func canPlay(url: URL) -> Bool { true }

    func load(url: URL, autoplay: Bool) throws {
        loadedURL = url
    }

    func play() {}
    func pause() {}
    func togglePlayback() {}
    func stop() {}

    func seek(to seconds: Double) {
        seekTimes.append(seconds)
    }

    func events() -> AsyncStream<PlaybackEvent> {
        eventStream
    }

    func send(_ event: PlaybackEvent) {
        continuation.yield(event)
    }
}
