import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import iptv

@MainActor
@Suite(.serialized)
struct SessionManagerTests {
    private let credentialStore = TestProviderCredentialStore()

    @Test func catalogRefreshPolicyRefreshesMissingAndExpiredTimestamps() {
        let now = Date(timeIntervalSince1970: 10_000)

        #expect(CatalogRefreshPolicy.isStale(lastSuccessfulSync: nil, now: now, maxAge: 100))
        #expect(CatalogRefreshPolicy.isStale(lastSuccessfulSync: now.addingTimeInterval(-100), now: now, maxAge: 100))
        #expect(!CatalogRefreshPolicy.isStale(lastSuccessfulSync: now.addingTimeInterval(-99), now: now, maxAge: 100))
    }

    @Test func loadWithoutActiveProviderSetsNoProviderState() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerManager = ProviderManager(database: database, credentialStore: credentialStore)
            try providerManager.loadActive()

            #expect(providerManager.hasActiveProvider == false)
            #expect(providerManager.session == nil)
        }
    }

    @Test func loadWithActiveProviderSetsProviderState() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)

            let providerManager = ProviderManager(database: database, credentialStore: credentialStore)
            try providerManager.loadActive()

            #expect(providerManager.hasActiveProvider == true)
            #expect(providerManager.session != nil)
            #expect(providerManager.session?.providerID == providerID)
        }
    }

    @Test func initializeCreatesAnActiveProviderSession() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerManager = ProviderManager(database: database, credentialStore: credentialStore)
            try providerManager.initialize(
                .init(
                    id: nil,
                    kind: .xtream,
                    name: "Bootstrap",
                    username: "user",
                    password: "pass",
                    endpoint: #require(URL(string: "https://example.com")),
                    allowsInsecureHTTP: false
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

    @Test func initializeClearsExistingLocalLibraryRows() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            try insertProvider(name: "Primary", isActive: true, database: database)
            try insertLibraryRows(database)

            let providerManager = ProviderManager(database: database, credentialStore: credentialStore)
            try providerManager.loadActive()
            try providerManager.initialize(
                .init(
                    id: nil,
                    kind: .xtream,
                    name: "Replacement",
                    username: "user",
                    password: "pass",
                    endpoint: #require(URL(string: "https://replacement.example.com")),
                    allowsInsecureHTTP: false
                )
            )

            let counts = try libraryCounts(database)
            #expect(counts.categories == 0)
            #expect(counts.media == 0)
        }
    }

    @Test func providerSwitchClearsCatalogAndRequiresFreshSync() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            try insertProvider(name: "Primary", isActive: true, database: database)
            let nextProviderID = try insertProvider(name: "Next", isActive: false, database: database)
            try insertLibraryRows(database)

            let providerManager = ProviderManager(database: database, credentialStore: credentialStore)
            try providerManager.loadActive()
            try providerManager.change(to: nextProviderID)

            let counts = try libraryCounts(database)
            let nextProvider = try database.read { try Provider.find($0, key: nextProviderID) }

            #expect(counts.categories == 0)
            #expect(counts.media == 0)
            #expect(nextProvider.isActive)
            #expect(!nextProvider.isInitialized)
            #expect(providerManager.requiresOnboarding)
        }
    }

    @Test func providerEditClearsCatalogAndRequiresFreshSync() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            try insertLibraryRows(database)

            let providerManager = ProviderManager(database: database, credentialStore: credentialStore)
            try providerManager.loadActive()
            try providerManager.update(
                provider: .init(
                    id: providerID,
                    kind: .xtream,
                    name: "Edited",
                    username: "user",
                    password: "pass",
                    endpoint: #require(URL(string: "https://edited.example.com")),
                    allowsInsecureHTTP: false
                )
            )

            let counts = try libraryCounts(database)
            let provider = try database.read { try Provider.find($0, key: providerID) }

            #expect(counts.categories == 0)
            #expect(counts.media == 0)
            #expect(provider.isActive)
            #expect(!provider.isInitialized)
            #expect(providerManager.requiresOnboarding)
        }
    }

    @Test func clearRemovesProviderAndLibraryRows() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            try insertProvider(name: "Primary", isActive: true, database: database)
            try insertLibraryRows(database)

            let providerManager = ProviderManager(database: database, credentialStore: credentialStore)
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
        let database = try testAppDatabase()
        return try operation(database)
    }

    private func resetDatabase(_ database: any DatabaseWriter) throws {
        try database.write { db in
            try CategoryPrefixVisibility.delete().execute(db)
            try Media.delete().execute(db)
            try Category.delete().execute(db)
            try Provider.delete().execute(db)
        }
    }

    private func libraryCounts(_ database: any DatabaseWriter) throws -> (categories: Int, media: Int) {
        try database.read {
            (
                try Category.fetchCount($0),
                try Media.fetchCount($0)
            )
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
        let credentialReference = "session-manager-\(UUID().uuidString)"
        try credentialStore.setPassword("pass", for: credentialReference)

        return try database.write { db in
            let provider = try Provider.insert {
                Provider.Draft(
                    id: nil,
                    kind: .xtream,
                    name: name,
                    username: "user",
                    credentialReference: credentialReference,
                    endpoint: endpoint,
                    allowsInsecureHTTP: false,
                    isInitialized: isInitialized,
                    isActive: isActive
                )
            }
            .returning(\.self)
            .fetchOne(db)!
            return provider.id
        }
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
