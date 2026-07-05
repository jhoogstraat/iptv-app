import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import iptv

@MainActor
@Suite(.serialized)
struct SessionManagerTests {
    @Test func loadWithoutActiveProviderSetsNoProviderState() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerManager = ProviderManager(database: database)
            try providerManager.loadActive()

            #expect(providerManager.hasActiveProvider == false)
            #expect(providerManager.session == nil)
        }
    }

    @Test func loadWithActiveProviderSetsProviderState() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)

            let providerManager = ProviderManager(database: database)
            try providerManager.loadActive()

            #expect(providerManager.hasActiveProvider == true)
            #expect(providerManager.session != nil)
            #expect(providerManager.session?.providerID == providerID)
        }
    }

    @Test func initializeCreatesAnActiveProviderSession() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerManager = ProviderManager(database: database)
            try providerManager.initialize(
                .init(
                    id: nil,
                    kind: .xtream,
                    name: "Bootstrap",
                    username: "user",
                    password: "pass",
                    endpoint: #require(URL(string: "https://example.com")),
                    isActive: true
                )
            )

            #expect(providerManager.hasActiveProvider == true)
            #expect(providerManager.session != nil)

            let activeProviderCount = try database.read {
                try Provider.where { $0.isActive.eq(true) }.fetchCount($0)
            }

            #expect(activeProviderCount == 1)
        }
    }

    @Test func clearRemovesProviderAndLibraryRows() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            try insertProvider(name: "Primary", isActive: true, database: database)
            try insertLibraryRows(database)

            let providerManager = ProviderManager(database: database)
            try providerManager.loadActive()
            try providerManager.delete(provider: try #require(providerManager.session?.providerID))

            #expect(providerManager.hasActiveProvider == false)
            #expect(providerManager.session == nil)

            let counts = try database.read {
                (
                    try Provider.fetchCount($0),
                    try Category.fetchCount($0),
                    try Media.fetchCount($0)
                )
            }

            #expect(counts.0 == 0)
            #expect(counts.1 == 0)
            #expect(counts.2 == 0)
        }
    }

    private func withTestDatabase<T>(_ operation: (any DatabaseWriter) throws -> T) throws -> T {
        let database = try appDatabase()
        return try operation(database)
    }

    private func resetDatabase(_ database: any DatabaseWriter) throws {
        try database.write { db in
            try Media.delete().execute(db)
            try Category.delete().execute(db)
            try Provider.delete().execute(db)
        }
    }

    @discardableResult
    private func insertProvider(
        name: String,
        isActive: Bool,
        isInitialized: Bool = true,
        database: any DatabaseWriter
    ) throws -> Provider.ID {
        let endpoint = try #require(URL(string: "https://example.com"))
        var providerID: Provider.ID?

        try database.write { db in
            let provider = try Provider.insert {
                Provider.Draft(
                    id: nil,
                    kind: .xtream,
                    name: name,
                    username: "user",
                    password: "pass",
                    endpoint: endpoint,
                    isActive: isActive
                )
            }
            .returning(\.self)
            .fetchOne(db)!

            providerID = provider.id

            try Provider.find(provider.id).update { $0.isInitialized = #bind(isInitialized) }.execute(db)
        }

        return try #require(providerID)
    }

    private func insertLibraryRows(_ database: any DatabaseWriter) throws {
        try database.write { db in
            try #sql("""
            INSERT INTO "categories" ("sourceID", "type", "title", "updatedAt")
            VALUES ('movies', 0, 'Movies', datetime())
            """).execute(db)

            let categoryID = Int(db.lastInsertedRowID)

            try #sql("""
            INSERT INTO "media" ("sourceID", "type", "title", "categoryID", "tmdbID", "coverURL", "rating")
            VALUES (1, 0, 'Movie One', \(categoryID), NULL, NULL, NULL)
            """).execute(db)
        }
    }
}
