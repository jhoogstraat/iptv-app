//
//  AppPersistence.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import OSLog
import Foundation
import SQLiteData

func appDatabase(
    path: String? = nil,
    credentialStore: any ProviderCredentialStoring = KeychainProviderCredentialStore()
) throws -> any DatabaseWriter {
    @Dependency(\.context) var context
    
    var configuration = Configuration()
    configuration.journalMode = .wal
#if DEBUG
    configuration.prepareDatabase { db in
//        db.trace(options: .profile) {
//            if context == .preview {
//                print("\($0.expandedDescription)")
//            } else {
//                logger.debug("\($0.expandedDescription)")
//            }
//        }
    }
#endif
    
    let database = try defaultDatabase(path: path, configuration: configuration)
    logger.info("open '\(database.path)'")
    
    var migrator = DatabaseMigrator()
    
#if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
#endif
    
    migrator.registerMigration("Create tables") { db in
        try #sql("""
        CREATE TABLE "providers" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "name" TEXT NOT NULL,
            "username" TEXT NOT NULL,
            "credentialReference" TEXT NOT NULL,
            "endpoint" TEXT NOT NULL,
            "allowsInsecureHTTP" INTEGER NOT NULL DEFAULT 0,
            "kind" TEXT NOT NULL DEFAULT 'xtream',
            "isInitialized" INTEGER NOT NULL DEFAULT 0,
            "isActive" INTEGER NOT NULL DEFAULT 0,
            "lastSyncedAt" TEXT,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) STRICT
        """).execute(db)

        try #sql("""
        CREATE TABLE "categories"(
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "sourceID" TEXT NOT NULL,
            "type" INTEGER NOT NULL,
            "title" TEXT NOT NULL,
            "updatedAt" TEXT,
            UNIQUE ("sourceID", "type")
        ) STRICT
        """).execute(db)

        try #sql("""
        CREATE TABLE "media" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "sourceID" INTEGER NOT NULL,
            "type" INTEGER NOT NULL,
            "title" TEXT NOT NULL,
            "categoryID" INTEGER,
            "tmdbID" TEXT,
            "coverURL" TEXT,
            "rating" REAL,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            "parentSeriesID" INTEGER,
            "seasonNumber" INTEGER,
            "episodeNumber" INTEGER,
            "containerExtension" TEXT,
            "synopsis" TEXT,
            "releaseDate" TEXT,
            "runtimeSeconds" INTEGER,
            "genre" TEXT,
            "cast" TEXT,
            "director" TEXT,
            "trailer" TEXT,
            "addedAt" TEXT,
            "backdropURL" TEXT,
            "country" TEXT,
            "epgChannelID" TEXT,
            "supportsCatchup" INTEGER NOT NULL DEFAULT 0,
            "catchupDays" INTEGER,
            UNIQUE ("sourceID", "type"),
            FOREIGN KEY ("categoryID") REFERENCES "categories"("id")
        ) STRICT
        """).execute(db)

        try #sql("""
        CREATE TABLE "category_prefix_visibility" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "providerID" INTEGER NOT NULL,
            "groupKey" TEXT NOT NULL,
            "isHidden" INTEGER NOT NULL DEFAULT 1,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE ("providerID", "groupKey"),
            FOREIGN KEY ("providerID") REFERENCES "providers"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)

        try #sql("""
        CREATE TABLE "series_seasons" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "seriesID" INTEGER NOT NULL,
            "seasonNumber" INTEGER NOT NULL,
            "title" TEXT NOT NULL,
            "overview" TEXT,
            "episodeCount" INTEGER,
            "coverURL" TEXT,
            "releaseDate" TEXT,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE ("seriesID", "seasonNumber"),
            FOREIGN KEY ("seriesID") REFERENCES "media"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)

        try #sql("""
        CREATE TABLE "user_profiles" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "name" TEXT NOT NULL,
            "createdAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) STRICT
        """).execute(db)

        try #sql("""
        INSERT INTO "user_profiles" ("id", "name") VALUES (1, 'Primary')
        """).execute(db)

        try #sql("""
        CREATE TABLE "watch_activity" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "profileID" INTEGER NOT NULL DEFAULT 1,
            "providerID" INTEGER NOT NULL,
            "mediaType" INTEGER NOT NULL,
            "sourceID" INTEGER NOT NULL,
            "title" TEXT NOT NULL,
            "artworkURL" TEXT,
            "categoryTitle" TEXT,
            "currentTime" REAL NOT NULL DEFAULT 0,
            "duration" REAL,
            "completed" INTEGER NOT NULL DEFAULT 0,
            "lastWatchedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            "writeSessionStartedAt" TEXT,
            "writeGeneration" INTEGER NOT NULL DEFAULT 0,
            UNIQUE ("profileID", "providerID", "mediaType", "sourceID"),
            FOREIGN KEY ("profileID") REFERENCES "user_profiles"("id") ON DELETE CASCADE,
            FOREIGN KEY ("providerID") REFERENCES "providers"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)

        try #sql("""
        CREATE INDEX "watch_activity_provider_last_watched_idx"
        ON "watch_activity" ("profileID", "providerID", "completed", "lastWatchedAt" DESC)
        """).execute(db)

        try #sql("""
        CREATE TABLE "favorites" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "profileID" INTEGER NOT NULL DEFAULT 1,
            "providerID" INTEGER NOT NULL,
            "mediaType" INTEGER NOT NULL,
            "sourceID" INTEGER NOT NULL,
            "title" TEXT NOT NULL,
            "artworkURL" TEXT,
            "categoryID" INTEGER,
            "categoryTitle" TEXT,
            "createdAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE ("profileID", "providerID", "mediaType", "sourceID"),
            FOREIGN KEY ("profileID") REFERENCES "user_profiles"("id") ON DELETE CASCADE,
            FOREIGN KEY ("providerID") REFERENCES "providers"("id") ON DELETE CASCADE,
            FOREIGN KEY ("categoryID") REFERENCES "categories"("id") ON DELETE SET NULL
        ) STRICT
        """).execute(db)

        try #sql("""
        CREATE INDEX "favorites_provider_updated_idx"
        ON "favorites" ("profileID", "providerID", "updatedAt" DESC)
        """).execute(db)

        try #sql("""
        CREATE TABLE "download_items" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "profileID" INTEGER NOT NULL,
            "providerID" INTEGER NOT NULL,
            "mediaType" INTEGER NOT NULL,
            "sourceID" INTEGER NOT NULL,
            "title" TEXT NOT NULL,
            "artworkURL" TEXT,
            "remoteURL" TEXT NOT NULL,
            "localPath" TEXT,
            "status" INTEGER NOT NULL DEFAULT 0,
            "errorMessage" TEXT,
            "createdAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE ("profileID", "providerID", "mediaType", "sourceID"),
            FOREIGN KEY ("profileID") REFERENCES "user_profiles"("id") ON DELETE CASCADE,
            FOREIGN KEY ("providerID") REFERENCES "providers"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)

        try #sql("""
        CREATE INDEX "download_items_profile_provider_updated_idx"
        ON "download_items" ("profileID", "providerID", "updatedAt" DESC)
        """).execute(db)
    }
    
    
    try migrator.migrate(database)
    
    return database
}


enum ProviderSourceKind: String, CaseIterable, Identifiable, Sendable, QueryBindable {
    case xtream = "xtream"

    var id: String { rawValue }
    var title: String { "Xtream API" }
    var subtitle: String { "Use one Xtream-compatible source for movies, series, and live TV." }
}

@Table
nonisolated struct Provider: Hashable, Identifiable, Sendable {
    let id: Int
    var kind: ProviderSourceKind = .xtream
    var name: String
    var username: String
    @Ephemeral var password = ""
    var credentialReference = ""
    var endpoint: URL
    var allowsInsecureHTTP = false
    var isInitialized: Bool = false
    var isActive: Bool = false
    var lastSyncedAt: Date? = nil
}

@Table("media")
nonisolated struct Media: Hashable, Identifiable, Sendable {
    let id: Int
    let sourceID: Int
    let type: MediaType
    let title: String
    let categoryID: Category.ID?
    let tmdbID: String?
    let coverURL: URL?
    let rating: Double?
    var parentSeriesID: Int? = nil
    var seasonNumber: Int? = nil
    var episodeNumber: Int? = nil
    var containerExtension: String? = nil
    var synopsis: String? = nil
    var releaseDate: Date? = nil
    var runtimeSeconds: Int? = nil
    var genre: String? = nil
    var cast: String? = nil
    var director: String? = nil
    var trailer: String? = nil
    var addedAt: Date? = nil
    var backdropURL: URL? = nil
    var country: String? = nil
    var epgChannelID: String? = nil
    var supportsCatchup = false
    var catchupDays: Int? = nil
    var updatedAt: Date = .now
}

@Table("series_seasons")
struct SeriesSeason: Hashable, Identifiable, Sendable {
    let id: Int
    let seriesID: Media.ID
    let seasonNumber: Int
    let title: String
    let overview: String?
    let episodeCount: Int?
    let coverURL: URL?
    let releaseDate: Date?
    var updatedAt: Date = .now
}

@Table
nonisolated struct Category: Hashable, Identifiable, Sendable {
    let id: Int
    let sourceID: String
    let type: MediaType
    let title: String
    var updatedAt: Date?
}

@Table("category_prefix_visibility")
nonisolated struct CategoryPrefixVisibility: Hashable, Identifiable, Sendable {
    let id: Int
    let providerID: Provider.ID
    let groupKey: String
    var isHidden: Bool = true
    var updatedAt: Date = .now
}

@Table("user_profiles")
nonisolated struct UserProfile: Hashable, Identifiable, Sendable {
    let id: Int
    var name: String
    var createdAt: Date = .now
    var updatedAt: Date = .now
}

enum UserProfileStore: Sendable {
    nonisolated static let primaryProfileID = 1
    nonisolated static let activeProfileIDKey = "userProfile.activeID"
    nonisolated static let revisionKey = "userProfile.revision"

    nonisolated static func activeProfileID(defaults: UserDefaults = .standard) -> UserProfile.ID {
        let storedID = defaults.integer(forKey: activeProfileIDKey)
        return storedID > 0 ? storedID : primaryProfileID
    }

    static func create(
        name rawName: String,
        database: any DatabaseWriter,
        defaults: UserDefaults = .standard
    ) throws -> UserProfile {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProfileError.emptyName }
        let now = Date()
        let profile = try database.write { db in
            try UserProfile.insert {
                UserProfile.Draft(id: nil, name: name, createdAt: now, updatedAt: now)
            }.execute(db)
            return try UserProfile.order { $0.id.desc() }.fetchOne(db)
        }
        guard let profile else { throw ProfileError.creationFailed }
        setActive(profile.id, defaults: defaults)
        return profile
    }

    static func rename(
        _ profile: UserProfile,
        to rawName: String,
        database: any DatabaseWriter,
        defaults: UserDefaults = .standard
    ) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProfileError.emptyName }
        try database.write { db in
            try UserProfile.find(profile.id).update {
                $0.name = name
                $0.updatedAt = Date()
            }.execute(db)
        }
        bumpRevision(defaults: defaults)
    }

    static func delete(
        _ profile: UserProfile,
        database: any DatabaseWriter,
        defaults: UserDefaults = .standard
    ) throws {
        try database.write { db in
            guard try UserProfile.fetchCount(db) > 1 else { throw ProfileError.lastProfile }
            try UserProfile.find(profile.id).delete().execute(db)
            if activeProfileID(defaults: defaults) == profile.id,
               let replacement = try UserProfile.order(by: { $0.id.asc() }).fetchOne(db) {
                defaults.set(replacement.id, forKey: activeProfileIDKey)
            }
        }
        bumpRevision(defaults: defaults)
    }

    nonisolated static func setActive(
        _ profileID: UserProfile.ID,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(profileID, forKey: activeProfileIDKey)
        bumpRevision(defaults: defaults)
        FavoriteStore.bumpRevision(defaults: defaults)
    }

    nonisolated private static func bumpRevision(defaults: UserDefaults) {
        defaults.set(defaults.integer(forKey: revisionKey) &+ 1, forKey: revisionKey)
    }

    enum ProfileError: LocalizedError {
        case emptyName
        case lastProfile
        case creationFailed

        var errorDescription: String? {
            switch self {
            case .emptyName: "Enter a profile name."
            case .lastProfile: "At least one profile is required."
            case .creationFailed: "The profile could not be created."
            }
        }
    }
}

@Table("watch_activity")
nonisolated struct WatchActivity: Hashable, Identifiable, Sendable {
    let id: Int
    let profileID: UserProfile.ID
    let providerID: Provider.ID
    let mediaType: MediaType
    let sourceID: Int
    var title: String
    var artworkURL: URL?
    var categoryTitle: String?
    var currentTime: Double = 0
    var duration: Double?
    var completed: Bool = false
    var lastWatchedAt: Date = .now
    var updatedAt: Date = .now
    var writeSessionStartedAt: Date?
    var writeGeneration: Int64 = 0

    var progressFraction: Double {
        guard let duration, duration > 0 else { return 0 }
        return Swift.min(Swift.max(currentTime / duration, 0), 1)
    }

    var remainingSeconds: Double? {
        guard let duration, duration > 0 else { return nil }
        return Swift.max(duration - currentTime, 0)
    }

    var isResumeEligible: Bool {
        WatchActivityStore.isResumeEligible(
            currentTime: currentTime,
            duration: duration,
            completed: completed
        )
    }
}

@Table("favorites")
nonisolated struct Favorite: Hashable, Identifiable, Sendable {
    let id: Int
    let profileID: UserProfile.ID
    let providerID: Provider.ID
    let mediaType: MediaType
    let sourceID: Int
    var title: String
    var artworkURL: URL?
    var categoryID: Category.ID?
    var categoryTitle: String?
    var createdAt: Date = .now
    var updatedAt: Date = .now
}

struct FavoriteItem: Hashable, Identifiable, Sendable {
    let favorite: Favorite
    let media: Media?
    let category: Category?

    init(favorite: Favorite, media: Media?, category: Category? = nil) {
        self.favorite = favorite
        self.media = media
        self.category = category
    }

    var id: Favorite.ID { favorite.id }
    var mediaType: MediaType { media?.type ?? favorite.mediaType }
    var sourceID: Int { media?.sourceID ?? favorite.sourceID }
    var title: String { media?.title ?? favorite.title }
    var artworkURL: URL? { media?.coverURL ?? media?.backdropURL ?? favorite.artworkURL }
    var categoryTitle: String? { category?.title ?? favorite.categoryTitle }
    var isAvailableLocally: Bool { media != nil }
}

enum WatchActivityStore: Sendable {
    struct WriteStamp: Equatable, Sendable {
        let sessionStartedAt: Date
        let generation: UInt64

        init(sessionStartedAt: Date, generation: UInt64) {
            self.sessionStartedAt = sessionStartedAt
            self.generation = generation
        }
    }

    nonisolated static let minimumResumeSeconds = 30.0
    nonisolated static let minimumRemainingSeconds = 30.0
    nonisolated static let completionFraction = 0.9

    nonisolated static func isResumeEligible(
        currentTime: Double,
        duration: Double?,
        completed: Bool
    ) -> Bool {
        guard !completed, currentTime.isFinite, currentTime >= minimumResumeSeconds else {
            return false
        }

        guard let duration, duration.isFinite, duration > 0 else {
            return true
        }

        let remaining = duration - currentTime
        return remaining >= minimumRemainingSeconds
            && (currentTime / duration) < completionFraction
    }

    nonisolated static func isCompleted(currentTime: Double, duration: Double?) -> Bool {
        guard currentTime.isFinite,
              let duration,
              duration.isFinite,
              duration > 0
        else { return false }

        return duration - currentTime <= minimumRemainingSeconds
            || (currentTime / duration) >= completionFraction
    }

    static func resumeTime(
        for media: Media,
        providerID: Provider.ID,
        database suppliedDatabase: (any DatabaseWriter)? = nil
    ) -> Double? {
        guard let activity = activity(for: media, providerID: providerID, database: suppliedDatabase),
              activity.isResumeEligible
        else { return nil }

        return activity.currentTime
    }

    static func activity(
        for media: Media,
        providerID: Provider.ID,
        database suppliedDatabase: (any DatabaseWriter)? = nil
    ) -> WatchActivity? {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase
        let profileID = UserProfileStore.activeProfileID()

        do {
            return try database.read { db in
                try WatchActivity
                    .where {
                        $0.profileID.eq(profileID)
                            .and($0.providerID.eq(providerID))
                            .and($0.mediaType.eq(media.type))
                            .and($0.sourceID.eq(media.sourceID))
                    }
                    .fetchOne(db)
            }
        } catch {
            logger.warning("Failed to read watch activity: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func unfinishedActivities(
        for providerID: Provider.ID,
        limit: Int = 20,
        database suppliedDatabase: (any DatabaseWriter)? = nil
    ) -> [WatchActivity] {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase
        let profileID = UserProfileStore.activeProfileID()

        do {
            let activities = try database.read { db in
                try WatchActivity
                    .where {
                        $0.profileID.eq(profileID)
                            .and($0.providerID.eq(providerID))
                            .and($0.completed.eq(false))
                    }
                    .fetchAll(db)
            }

            return Array(
                activities
                    .filter(\.isResumeEligible)
                    .sorted(by: activityOrdering)
                    .prefix(Swift.max(limit, 0))
            )
        } catch {
            logger.warning("Failed to read unfinished watch activity: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    nonisolated static func activityOrdering(_ lhs: WatchActivity, _ rhs: WatchActivity) -> Bool {
        if lhs.lastWatchedAt != rhs.lastWatchedAt {
            return lhs.lastWatchedAt > rhs.lastWatchedAt
        }

        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        if lhs.mediaType != rhs.mediaType {
            return lhs.mediaType.rawValue < rhs.mediaType.rawValue
        }
        if lhs.sourceID != rhs.sourceID {
            return lhs.sourceID < rhs.sourceID
        }
        return lhs.id < rhs.id
    }

    nonisolated static func recordProgress(
        for media: Media,
        providerID: Provider.ID,
        currentTime rawCurrentTime: Double,
        duration rawDuration: Double?,
        completed explicitlyCompleted: Bool,
        writeStamp: WriteStamp,
        database: any DatabaseWriter
    ) async -> Bool {
        guard media.type == .movie || media.type == .episode else { return false }
        guard rawCurrentTime.isFinite,
              writeStamp.sessionStartedAt.timeIntervalSinceReferenceDate.isFinite,
              writeStamp.generation <= UInt64(Int64.max)
        else { return false }

        let currentTime = Swift.max(rawCurrentTime, 0)
        let duration = resolvedDuration(rawDuration, mediaRuntimeSeconds: media.runtimeSeconds)
        let completed = explicitlyCompleted || isCompleted(currentTime: currentTime, duration: duration)
        let storedCurrentTime = completed ? Swift.max(currentTime, duration ?? currentTime) : currentTime
        let writeGeneration = Int64(writeStamp.generation)
        let now = Date()
        let profileID = UserProfileStore.activeProfileID()

        do {
            return try await database.write { db in
                let existing = try WatchActivity
                    .where {
                        $0.profileID.eq(profileID)
                            .and($0.providerID.eq(providerID))
                            .and($0.mediaType.eq(media.type))
                            .and($0.sourceID.eq(media.sourceID))
                    }
                    .fetchOne(db)

                if let existing,
                   !accepts(writeStamp, generation: writeGeneration, after: existing) {
                    return false
                }

                let categoryTitle: String? = if let categoryID = media.categoryID {
                    try Category
                        .select(\.title)
                        .where { $0.id.eq(categoryID) }
                        .fetchOne(db)
                } else {
                    nil
                }
                let artworkURL = media.backdropURL ?? media.coverURL

                if let existing {
                    try WatchActivity.find(existing.id).update {
                        $0.title = media.title
                        $0.artworkURL = #bind(artworkURL)
                        $0.categoryTitle = #bind(categoryTitle)
                        $0.currentTime = storedCurrentTime
                        $0.duration = #bind(duration)
                        $0.completed = completed
                        $0.lastWatchedAt = now
                        $0.updatedAt = now
                        $0.writeSessionStartedAt = #bind(writeStamp.sessionStartedAt)
                        $0.writeGeneration = #bind(writeGeneration)
                    }.execute(db)
                } else {
                    try WatchActivity.insert {
                        WatchActivity.Draft(
                            id: nil,
                            profileID: profileID,
                            providerID: providerID,
                            mediaType: media.type,
                            sourceID: media.sourceID,
                            title: media.title,
                            artworkURL: artworkURL,
                            categoryTitle: categoryTitle,
                            currentTime: storedCurrentTime,
                            duration: duration,
                            completed: completed,
                            lastWatchedAt: now,
                            updatedAt: now,
                            writeSessionStartedAt: writeStamp.sessionStartedAt,
                            writeGeneration: writeGeneration
                        )
                    }.execute(db)
                }

                return true
            }
        } catch {
            logger.warning("Failed to record watch activity: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    nonisolated static func deleteActivity(for providerID: Provider.ID, in db: Database) throws {
        try WatchActivity
            .where { $0.providerID.eq(providerID) }
            .delete()
            .execute(db)
    }

    nonisolated private static func accepts(
        _ writeStamp: WriteStamp,
        generation: Int64,
        after existing: WatchActivity
    ) -> Bool {
        guard let storedSessionStartedAt = existing.writeSessionStartedAt else {
            return true
        }
        if writeStamp.sessionStartedAt != storedSessionStartedAt {
            return writeStamp.sessionStartedAt > storedSessionStartedAt
        }
        return generation > existing.writeGeneration
    }

    nonisolated private static func resolvedDuration(_ rawDuration: Double?, mediaRuntimeSeconds: Int?) -> Double? {
        if let rawDuration, rawDuration.isFinite, rawDuration > 0 {
            return rawDuration
        }

        if let mediaRuntimeSeconds, mediaRuntimeSeconds > 0 {
            return Double(mediaRuntimeSeconds)
        }

        return nil
    }
}


enum FavoriteStore: Sendable {
    enum MutationResult: Equatable, Sendable {
        case added
        case removed

        var isFavorite: Bool {
            self == .added
        }
    }

    enum MutationError: LocalizedError, Equatable {
        case missingProvider

        var errorDescription: String? {
            switch self {
            case .missingProvider:
                "A provider is required to update Favorites."
            }
        }
    }

    nonisolated static let revisionKey = "library.favorites.revision"

    static func isFavorite(
        _ media: Media,
        providerID: Provider.ID?,
        database suppliedDatabase: (any DatabaseWriter)? = nil
    ) -> Bool {
        favorite(for: media, providerID: providerID, database: suppliedDatabase) != nil
    }

    static func favorite(
        for media: Media,
        providerID: Provider.ID?,
        database suppliedDatabase: (any DatabaseWriter)? = nil
    ) -> Favorite? {
        guard let providerID else { return nil }
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase
        let profileID = UserProfileStore.activeProfileID()

        do {
            return try database.read { db in
                try Favorite
                    .where {
                        $0.profileID.eq(profileID)
                            .and($0.providerID.eq(providerID))
                            .and($0.mediaType.eq(media.type))
                            .and($0.sourceID.eq(media.sourceID))
                    }
                    .fetchOne(db)
            }
        } catch {
            logger.warning("Failed to read favorite: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func favorites(
        for providerID: Provider.ID?,
        database suppliedDatabase: (any DatabaseWriter)? = nil
    ) -> [FavoriteItem] {
        guard let providerID else { return [] }
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase
        let profileID = UserProfileStore.activeProfileID()

        do {
            return try database.read { db in
                let favorites = try Favorite
                    .where { $0.profileID.eq(profileID).and($0.providerID.eq(providerID)) }
                    .fetchAll(db)
                    .sorted(by: favoriteOrdering)

                let mediaRows = try Media.fetchAll(db)
                let mediaByKey = Dictionary(
                    mediaRows.map { (contentKey(mediaType: $0.type, sourceID: $0.sourceID), $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                let categoryByID = Dictionary(
                    uniqueKeysWithValues: try Category.fetchAll(db).map { ($0.id, $0) }
                )

                return favorites.map { favorite in
                    let media = mediaByKey[
                        contentKey(mediaType: favorite.mediaType, sourceID: favorite.sourceID)
                    ]
                    return FavoriteItem(
                        favorite: favorite,
                        media: media,
                        category: media?.categoryID.flatMap { categoryByID[$0] }
                    )
                }
            }
        } catch {
            logger.warning("Failed to read favorites: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func toggle(
        _ media: Media,
        providerID: Provider.ID?,
        categoryTitle suppliedCategoryTitle: String? = nil,
        database suppliedDatabase: (any DatabaseWriter)? = nil,
        defaults: UserDefaults = .standard
    ) throws -> MutationResult {
        guard let providerID else { throw MutationError.missingProvider }
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase
        let now = Date()
        let profileID = UserProfileStore.activeProfileID(defaults: defaults)

        let result = try database.write { db in
            let existing = try Favorite
                .where {
                    $0.profileID.eq(profileID)
                        .and($0.providerID.eq(providerID))
                        .and($0.mediaType.eq(media.type))
                        .and($0.sourceID.eq(media.sourceID))
                }
                .fetchOne(db)

            if let existing {
                try Favorite.find(existing.id).delete().execute(db)
                return MutationResult.removed
            }

            try insert(
                media,
                profileID: profileID,
                providerID: providerID,
                categoryTitle: suppliedCategoryTitle,
                now: now,
                in: db
            )
            return MutationResult.added
        }

        bumpRevision(defaults: defaults)
        return result
    }

    static func add(
        _ media: Media,
        providerID: Provider.ID?,
        categoryTitle suppliedCategoryTitle: String? = nil,
        database suppliedDatabase: (any DatabaseWriter)? = nil,
        defaults: UserDefaults = .standard
    ) throws -> MutationResult {
        guard let providerID else { throw MutationError.missingProvider }
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase
        let now = Date()
        let profileID = UserProfileStore.activeProfileID(defaults: defaults)

        try database.write { db in
            try insert(
                media,
                profileID: profileID,
                providerID: providerID,
                categoryTitle: suppliedCategoryTitle,
                now: now,
                in: db
            )
        }

        bumpRevision(defaults: defaults)
        return .added
    }

    static func remove(
        _ media: Media,
        providerID: Provider.ID?,
        database suppliedDatabase: (any DatabaseWriter)? = nil,
        defaults: UserDefaults = .standard
    ) throws -> MutationResult {
        guard let providerID else { throw MutationError.missingProvider }
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase
        let profileID = UserProfileStore.activeProfileID(defaults: defaults)

        try database.write { db in
            try Favorite
                .where {
                    $0.profileID.eq(profileID)
                        .and($0.providerID.eq(providerID))
                        .and($0.mediaType.eq(media.type))
                        .and($0.sourceID.eq(media.sourceID))
                }
                .delete()
                .execute(db)
        }

        bumpRevision(defaults: defaults)
        return .removed
    }

    static func remove(
        _ favorite: Favorite,
        database suppliedDatabase: (any DatabaseWriter)? = nil,
        defaults: UserDefaults = .standard
    ) throws -> MutationResult {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase

        try database.write { db in
            try Favorite.find(favorite.id).delete().execute(db)
        }

        bumpRevision(defaults: defaults)
        return .removed
    }

    nonisolated static func deleteFavorites(for providerID: Provider.ID, in db: Database) throws {
        try Favorite
            .where { $0.providerID.eq(providerID) }
            .delete()
            .execute(db)
    }

    nonisolated static func contentKey(mediaType: MediaType, sourceID: Int) -> String {
        "\(mediaType.rawValue):\(sourceID)"
    }

    nonisolated static func favoriteOrdering(_ lhs: Favorite, _ rhs: Favorite) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        if lhs.mediaType != rhs.mediaType {
            return lhs.mediaType.rawValue < rhs.mediaType.rawValue
        }
        if lhs.sourceID != rhs.sourceID {
            return lhs.sourceID < rhs.sourceID
        }
        return lhs.id < rhs.id
    }

    nonisolated private static func insert(
        _ media: Media,
        profileID: UserProfile.ID,
        providerID: Provider.ID,
        categoryTitle suppliedCategoryTitle: String?,
        now: Date,
        in db: Database
    ) throws {
        let categoryTitle = suppliedCategoryTitle ?? categoryTitle(for: media, in: db)
        let artworkURL = media.coverURL ?? media.backdropURL

        try Favorite.insert {
            Favorite.Draft(
                id: nil,
                profileID: profileID,
                providerID: providerID,
                mediaType: media.type,
                sourceID: media.sourceID,
                title: media.title,
                artworkURL: artworkURL,
                categoryID: media.categoryID,
                categoryTitle: categoryTitle,
                createdAt: now,
                updatedAt: now
            )
        } onConflict: {
            ($0.profileID, $0.providerID, $0.mediaType, $0.sourceID)
        } doUpdate: {
            $0.title = media.title
            $0.artworkURL = #bind(artworkURL)
            $0.categoryID = #bind(media.categoryID)
            $0.categoryTitle = #bind(categoryTitle)
            $0.updatedAt = now
        }.execute(db)
    }

    nonisolated static func bumpRevision(defaults: UserDefaults) {
        defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }

    nonisolated private static func categoryTitle(for media: Media, in db: Database) -> String? {
        guard let categoryID = media.categoryID else { return nil }
        return try? Category
            .select(\.title)
            .where { $0.id.eq(categoryID) }
            .fetchOne(db)
    }
}
enum MediaType: Int, QueryBindable {
   case movie = 0, series = 1, episode = 2, live = 3
}

private nonisolated let logger = Logger(subsystem: "IPTV", category: "Database")
