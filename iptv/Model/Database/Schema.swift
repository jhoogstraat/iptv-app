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

enum MediaType: Int, QueryBindable {
   case movie = 0, series = 1, episode = 2, live = 3
}

private nonisolated let logger = Logger(subsystem: "IPTV", category: "Database")
