import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import iptv

@MainActor
@Suite(.dependency(\.defaultDatabase, try appDatabase()))
struct SessionManagerTests {
    @Dependency(\.defaultDatabase) var database

    init() throws {
        try resetDatabase()
    }
    
    @Test func loadWithoutActiveProviderSetsNoProviderState() throws {
        let providerManager = ProviderManager()
        try providerManager.loadActive()

        #expect(providerManager.hasActiveProvider == false)
        #expect(providerManager.activeProviderID == nil)
        #expect(providerManager.syncManager == nil)
    }

    @Test func loadWithActiveProviderSetsProviderState() throws {
        let providerID = try insertProvider(name: "Primary", isActive: true)

        let providerManager = ProviderManager()
        try providerManager.loadActive()

        #expect(providerManager.hasActiveProvider == true)
        #expect(providerManager.syncManager != nil)
        #expect(providerManager.activeProviderID == providerID)
    }

    @Test func initializeCreatesAnActiveProviderSession() throws {
        let providerManager = ProviderManager()
        try providerManager.initialize(
            .init(
                id: nil,
                name: "Bootstrap",
                username: "user",
                password: "pass",
                endpoint: #require(URL(string: "https://example.com")),
                isActive: true
            )
        )

        #expect(providerManager.hasActiveProvider == true)
        #expect(providerManager.syncManager != nil)

        let activeProviderCount = try database.read {
            try Provider.where { $0.isActive.eq(true) }.fetchCount($0)
        }

        #expect(activeProviderCount == 1)
    }

    @Test func clearRemovesProviderAndLibraryRows() throws {
        try insertProvider(name: "Primary", isActive: true)
        try insertLibraryRows()

        let providerManager = ProviderManager()
        try providerManager.loadActive()
        try providerManager.delete(provider: providerManager.activeProviderID!)

        #expect(providerManager.hasActiveProvider == false)
        #expect(providerManager.activeProviderID == nil)
        #expect(providerManager.syncManager == nil)

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

    private func resetDatabase() throws {
        try database.write { db in
            try Media.delete().execute(db)
            try Category.delete().execute(db)
            try Provider.delete().execute(db)
        }
    }

    @discardableResult
    private func insertProvider(name: String, isActive: Bool) throws -> Provider.ID {
        let endpoint = try #require(URL(string: "https://example.com"))
        var providerID: Provider.ID?

        try database.write { db in
            let provider = try Provider.insert {
                Provider.Draft(
                    id: nil,
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
        }

        return try #require(providerID)
    }

    private func insertLibraryRows() throws {
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
