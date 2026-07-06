//
//  AppPersistence.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import OSLog
import Foundation
import SQLiteData
import xtream_swift

func appDatabase() throws -> any DatabaseWriter {
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
    
    let database = try defaultDatabase(configuration: configuration)
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
            "password" TEXT NOT NULL,
            "endpoint" TEXT NOT NULL,
            "kind" TEXT NOT NULL DEFAULT 'xtream',
            "isInitialized" INTEGER NOT NULL DEFAULT 0,
            "isActive" INTEGER NOT NULL DEFAULT 0,
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
        
    }
    
    migrator.registerMigration("Normalize provider base endpoints") { db in
        let providers = try Provider.fetchAll(db)
        for provider in providers {
            guard let normalized = try? XtreamEndpoint.normalizeBaseURL(provider.endpoint.absoluteString),
                  normalized != provider.endpoint
            else { continue }

            try Provider.find(provider.id).update { $0.endpoint = #bind(normalized) }.execute(db)
        }
    }

    migrator.registerMigration("Scope catalog identity and prefix visibility") { db in
        try #sql("""
        CREATE TABLE "new_categories"(
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "sourceID" TEXT NOT NULL,
            "type" INTEGER NOT NULL,
            "title" TEXT NOT NULL,
            "updatedAt" TEXT,
            UNIQUE ("sourceID", "type")
        ) STRICT
        """).execute(db)

        try #sql("""
        INSERT INTO "new_categories" ("id", "sourceID", "type", "title", "updatedAt")
        SELECT "id", "sourceID", "type", "title", "updatedAt" FROM "categories"
        """).execute(db)

        try #sql("""
        CREATE TABLE "new_media" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "sourceID" INTEGER NOT NULL,
            "type" INTEGER NOT NULL,
            "title" TEXT NOT NULL,
            "categoryID" INTEGER,
            "tmdbID" TEXT,
            "coverURL" TEXT,
            "rating" REAL,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE ("sourceID", "type"),
            FOREIGN KEY ("categoryID") REFERENCES "categories"("id")
        ) STRICT
        """).execute(db)

        try #sql("""
        INSERT INTO "new_media" ("id", "sourceID", "type", "title", "categoryID", "tmdbID", "coverURL", "rating", "updatedAt")
        SELECT "id", "sourceID", "type", "title", "categoryID", "tmdbID", "coverURL", "rating", "updatedAt" FROM "media"
        """).execute(db)

        try #sql("""
        DROP TABLE "media"
        """).execute(db)
        try #sql("""
        DROP TABLE "categories"
        """).execute(db)
        try #sql("""
        ALTER TABLE "new_categories" RENAME TO "categories"
        """).execute(db)
        try #sql("""
        ALTER TABLE "new_media" RENAME TO "media"
        """).execute(db)

        try #sql("""
        CREATE TABLE IF NOT EXISTS "category_prefix_visibility" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "providerID" INTEGER NOT NULL,
            "groupKey" TEXT NOT NULL,
            "isHidden" INTEGER NOT NULL DEFAULT 1,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE ("providerID", "groupKey"),
            FOREIGN KEY ("providerID") REFERENCES "providers"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)
    }

    migrator.registerMigration("Persist media metadata and series episodes") { db in
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "parentSeriesID" INTEGER
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "seasonNumber" INTEGER
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "episodeNumber" INTEGER
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "containerExtension" TEXT
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "synopsis" TEXT
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "releaseDate" TEXT
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "runtimeSeconds" INTEGER
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "genre" TEXT
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "cast" TEXT
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "director" TEXT
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "trailer" TEXT
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "addedAt" TEXT
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "backdropURL" TEXT
        """).execute(db)
        try #sql("""
        ALTER TABLE "media" ADD COLUMN "country" TEXT
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
    }

    migrator.registerMigration("Create provider scoped watch activity") { db in
        try #sql("""
        CREATE TABLE "watch_activity" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
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
            UNIQUE ("providerID", "mediaType", "sourceID"),
            FOREIGN KEY ("providerID") REFERENCES "providers"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)

        try #sql("""
        CREATE INDEX "watch_activity_provider_last_watched_idx"
        ON "watch_activity" ("providerID", "completed", "lastWatchedAt" DESC)
        """).execute(db)
    }

    migrator.registerMigration("Create provider scoped favorites") { db in
        try #sql("""
        CREATE TABLE "favorites" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "providerID" INTEGER NOT NULL,
            "mediaType" INTEGER NOT NULL,
            "sourceID" INTEGER NOT NULL,
            "title" TEXT NOT NULL,
            "artworkURL" TEXT,
            "categoryID" INTEGER,
            "categoryTitle" TEXT,
            "createdAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE ("providerID", "mediaType", "sourceID"),
            FOREIGN KEY ("providerID") REFERENCES "providers"("id") ON DELETE CASCADE,
            FOREIGN KEY ("categoryID") REFERENCES "categories"("id") ON DELETE SET NULL
        ) STRICT
        """).execute(db)

        try #sql("""
        CREATE INDEX "favorites_provider_updated_idx"
        ON "favorites" ("providerID", "updatedAt" DESC)
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
    var password: String
    var endpoint: URL
    var isInitialized: Bool = false
    var isActive: Bool = false
}

@Table("media")
struct Media: Hashable, Identifiable, Sendable {
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

@Table("watch_activity")
nonisolated struct WatchActivity: Hashable, Identifiable, Sendable {
    let id: Int
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

    var id: Favorite.ID { favorite.id }
    var mediaType: MediaType { media?.type ?? favorite.mediaType }
    var sourceID: Int { media?.sourceID ?? favorite.sourceID }
    var title: String { media?.title ?? favorite.title }
    var artworkURL: URL? { media?.coverURL ?? media?.backdropURL ?? favorite.artworkURL }
    var categoryTitle: String? { favorite.categoryTitle }
    var isAvailableLocally: Bool { media != nil }
}

enum WatchActivityStore: Sendable {
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

        do {
            return try database.read { db in
                try WatchActivity
                    .where {
                        $0.providerID.eq(providerID)
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

        do {
            let activities = try database.read { db in
                try WatchActivity
                    .where { $0.providerID.eq(providerID).and($0.completed.eq(false)) }
                    .fetchAll(db)
            }

            return Array(
                activities
                    .filter(\.isResumeEligible)
                    .sorted { lhs, rhs in
                        if lhs.lastWatchedAt != rhs.lastWatchedAt {
                            return lhs.lastWatchedAt > rhs.lastWatchedAt
                        }
                        if lhs.title.localizedStandardCompare(rhs.title) != .orderedSame {
                            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                        }
                        return lhs.sourceID < rhs.sourceID
                    }
                    .prefix(Swift.max(limit, 0))
            )
        } catch {
            logger.warning("Failed to read unfinished watch activity: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    nonisolated static func recordProgress(
        for media: Media,
        providerID: Provider.ID,
        currentTime rawCurrentTime: Double,
        duration rawDuration: Double?,
        completed explicitlyCompleted: Bool,
        database: any DatabaseWriter
    ) async {
        guard media.type == .movie || media.type == .episode else { return }
        guard rawCurrentTime.isFinite else { return }

        let currentTime = Swift.max(rawCurrentTime, 0)
        let duration = resolvedDuration(rawDuration, mediaRuntimeSeconds: media.runtimeSeconds)
        let completed = explicitlyCompleted || isCompleted(currentTime: currentTime, duration: duration)
        let storedCurrentTime = completed ? Swift.max(currentTime, duration ?? currentTime) : currentTime
        let now = Date()

        do {
            try await database.write { db in
                let categoryTitle: String? = if let categoryID = media.categoryID {
                    try? Category
                        .select(\.title)
                        .where { $0.id.eq(categoryID) }
                        .fetchOne(db)
                } else {
                    nil
                }

                let artworkURL = media.backdropURL ?? media.coverURL
                try WatchActivity.insert {
                    WatchActivity.Draft(
                        id: nil,
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
                        updatedAt: now
                    )
                } onConflict: {
                    ($0.providerID, $0.mediaType, $0.sourceID)
                } doUpdate: {
                    $0.title = media.title
                    $0.artworkURL = #bind(artworkURL)
                    $0.categoryTitle = #bind(categoryTitle)
                    $0.currentTime = storedCurrentTime
                    $0.duration = #bind(duration)
                    $0.completed = completed
                    $0.lastWatchedAt = now
                    $0.updatedAt = now
                }.execute(db)
            }
        } catch {
            logger.warning("Failed to record watch activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func deleteActivity(for providerID: Provider.ID, in db: Database) throws {
        try WatchActivity
            .where { $0.providerID.eq(providerID) }
            .delete()
            .execute(db)
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

        do {
            return try database.read { db in
                try Favorite
                    .where {
                        $0.providerID.eq(providerID)
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

        do {
            return try database.read { db in
                let favorites = try Favorite
                    .where { $0.providerID.eq(providerID) }
                    .fetchAll(db)
                    .sorted(by: favoriteOrdering)

                let mediaRows = try Media.fetchAll(db)
                let mediaByKey = Dictionary(
                    mediaRows.map { (contentKey(mediaType: $0.type, sourceID: $0.sourceID), $0) },
                    uniquingKeysWith: { first, _ in first }
                )

                return favorites.map { favorite in
                    FavoriteItem(
                        favorite: favorite,
                        media: mediaByKey[contentKey(mediaType: favorite.mediaType, sourceID: favorite.sourceID)]
                    )
                }
            }
        } catch {
            logger.warning("Failed to read favorites: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    @discardableResult
    static func toggle(
        _ media: Media,
        providerID: Provider.ID?,
        categoryTitle suppliedCategoryTitle: String? = nil,
        database suppliedDatabase: (any DatabaseWriter)? = nil,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if isFavorite(media, providerID: providerID, database: suppliedDatabase) {
            remove(media, providerID: providerID, database: suppliedDatabase, defaults: defaults)
            return false
        }

        add(media, providerID: providerID, categoryTitle: suppliedCategoryTitle, database: suppliedDatabase, defaults: defaults)
        return true
    }

    static func add(
        _ media: Media,
        providerID: Provider.ID?,
        categoryTitle suppliedCategoryTitle: String? = nil,
        database suppliedDatabase: (any DatabaseWriter)? = nil,
        defaults: UserDefaults = .standard
    ) {
        guard let providerID else { return }
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase
        let now = Date()

        do {
            try database.write { db in
                let categoryTitle = suppliedCategoryTitle ?? categoryTitle(for: media, in: db)
                let artworkURL = media.coverURL ?? media.backdropURL

                try Favorite.insert {
                    Favorite.Draft(
                        id: nil,
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
                    ($0.providerID, $0.mediaType, $0.sourceID)
                } doUpdate: {
                    $0.title = media.title
                    $0.artworkURL = #bind(artworkURL)
                    $0.categoryID = #bind(media.categoryID)
                    $0.categoryTitle = #bind(categoryTitle)
                    $0.updatedAt = now
                }.execute(db)
            }

            bumpRevision(defaults: defaults)
        } catch {
            logger.warning("Failed to save favorite: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func remove(
        _ media: Media,
        providerID: Provider.ID?,
        database suppliedDatabase: (any DatabaseWriter)? = nil,
        defaults: UserDefaults = .standard
    ) {
        guard let providerID else { return }
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase

        do {
            try database.write { db in
                try Favorite
                    .where {
                        $0.providerID.eq(providerID)
                            .and($0.mediaType.eq(media.type))
                            .and($0.sourceID.eq(media.sourceID))
                    }
                    .delete()
                    .execute(db)
            }

            bumpRevision(defaults: defaults)
        } catch {
            logger.warning("Failed to remove favorite: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func remove(
        _ favorite: Favorite,
        database suppliedDatabase: (any DatabaseWriter)? = nil,
        defaults: UserDefaults = .standard
    ) {
        @Dependency(\.defaultDatabase) var defaultDatabase
        let database = suppliedDatabase ?? defaultDatabase

        do {
            try database.write { db in
                try Favorite.find(favorite.id).delete().execute(db)
            }

            bumpRevision(defaults: defaults)
        } catch {
            logger.warning("Failed to remove favorite row: \(error.localizedDescription, privacy: .public)")
        }
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
        if lhs.title.localizedStandardCompare(rhs.title) != .orderedSame {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        if lhs.mediaType != rhs.mediaType {
            return lhs.mediaType.rawValue < rhs.mediaType.rawValue
        }
        return lhs.sourceID < rhs.sourceID
    }

    nonisolated private static func bumpRevision(defaults: UserDefaults) {
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
