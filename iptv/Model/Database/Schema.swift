//
//  AppPersistence.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import OSLog
import Foundation
import SQLiteData

func appDatabase() throws -> any DatabaseWriter {
    @Dependency(\.context) var context
    
    var configuration = Configuration()
    
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
            "isActive" INTEGER NOT NULL DEFAULT 0,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) STRICT
        """)
        .execute(db)
        
        try #sql("""
        CREATE TABLE "media" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "sourceID" INTEGER NOT NULL,
            "type" INTEGER NOT NULL,
            "title" TEXT NOT NULL,
            "categoryID" INTEGER REFERENCES "categories"("id"),
            "tmdbID" TEXT,
            "coverURL" TEXT,
            "rating" REAL,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) STRICT
        """)
        .execute(db)
        
        try #sql("""
        CREATE TABLE "categories"(
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "sourceID" TEXT NOT NULL,
            "type" INTEGER NOT NULL,
            "title" TEXT NOT NULL,
            "updatedAt" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE ("sourceID", "type")
        ) STRICT
        """)
        .execute(db)
    }
    try migrator.migrate(database)
    return database
}

@Table
nonisolated struct Provider: Hashable, Identifiable, Sendable {
    let id: Int
    var name: String
    var username: String
    var password: String
    var endpoint: URL
    var isActive: Bool
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
    var updatedAt: Date = .now
}
enum MediaType: Int, QueryBindable {
   case movie = 0, series = 1, episode = 2
}

@Table
nonisolated struct Category: Hashable, Identifiable, Sendable {
    let id: Int
    let sourceID: String
    let type: MediaType
    let title: String
    var updatedAt: Date = .now
}

private nonisolated let logger = Logger(subsystem: "IPTV", category: "Database")
