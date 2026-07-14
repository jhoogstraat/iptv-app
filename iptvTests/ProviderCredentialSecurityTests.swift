import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import iptv

@MainActor
@Suite(.serialized)
struct ProviderCredentialSecurityTests {
    @Test func createRelaunchUpdateAndDeleteKeepPasswordOutOfSQLite() throws {
        let credentials = TestProviderCredentialStore()
        try withTestDatabase(credentials: credentials) { database in
            let fields = ProviderFields(
                name: "Primary",
                endpoint: "example.com/player_api.php",
                username: "user",
                password: " secret with spaces "
            )
            let configuration = try #require(fields.build(id: nil, kind: .xtream))
            #expect(configuration.endpoint.absoluteString == "https://example.com")

            let manager = ProviderManager(database: database, credentialStore: credentials)
            try manager.initialize(configuration)

            let storedProvider = try database.read { db in
                let provider = try Provider.where(\.isActive).fetchOne(db)
                return try #require(provider)
            }
            let providerColumns = try database.read { db in
                try db.columns(in: "providers").map(\.name)
            }

            #expect(!providerColumns.contains("password"))
            #expect(storedProvider.credentialReference.isEmpty == false)
            #expect(credentials.storedPassword(for: storedProvider.credentialReference) == " secret with spaces ")
            #expect(manager.session?.providerID == storedProvider.id)

            let relaunchedManager = ProviderManager(database: database, credentialStore: credentials)
            try relaunchedManager.loadActive()
            #expect(relaunchedManager.accessState == .ready)
            #expect(relaunchedManager.session?.providerID == storedProvider.id)

            try relaunchedManager.update(
                provider: configurationWith(
                    id: storedProvider.id,
                    endpoint: storedProvider.endpoint,
                    password: "replacement-secret"
                )
            )

            let updatedProvider = try database.read { db in
                try Provider.find(db, key: storedProvider.id)
            }
            #expect(updatedProvider.credentialReference == storedProvider.credentialReference)
            #expect(credentials.storedPassword(for: storedProvider.credentialReference) == "replacement-secret")
            #expect(relaunchedManager.session?.providerID == storedProvider.id)

            try relaunchedManager.delete(provider: storedProvider.id)

            #expect(credentials.storedPassword(for: storedProvider.credentialReference) == nil)
            #expect(try database.read { try Provider.fetchCount($0) } == 0)
        }
    }

    @Test func freshDatabaseCreatesCompleteSchema() throws {
        let database = try testAppDatabase(credentialStore: TestProviderCredentialStore())

        try database.read { db in
            let expectedTables = [
                "providers",
                "categories",
                "media",
                "category_prefix_visibility",
                "series_seasons",
                "watch_activity",
                "favorites",
            ]
            for table in expectedTables {
                #expect(try db.tableExists(table))
            }

            let providerColumns = Set(try db.columns(in: "providers").map(\.name))
            #expect(providerColumns.contains("credentialReference"))
            #expect(!providerColumns.contains("password"))

            let mediaColumns = Set(try db.columns(in: "media").map(\.name))
            #expect(mediaColumns == [
                "id",
                "sourceID",
                "type",
                "title",
                "categoryID",
                "tmdbID",
                "coverURL",
                "rating",
                "updatedAt",
                "parentSeriesID",
                "seasonNumber",
                "episodeNumber",
                "containerExtension",
                "synopsis",
                "releaseDate",
                "runtimeSeconds",
                "genre",
                "cast",
                "director",
                "trailer",
                "addedAt",
                "backdropURL",
                "country",
            ])

            let watchActivityColumns = Set(try db.columns(in: "watch_activity").map(\.name))
            #expect(watchActivityColumns.contains("writeSessionStartedAt"))
            #expect(watchActivityColumns.contains("writeGeneration"))

            let watchActivityIndexes = Set(try db.indexes(on: "watch_activity").map(\.name))
            #expect(watchActivityIndexes.contains("watch_activity_provider_last_watched_idx"))
            let favoriteIndexes = Set(try db.indexes(on: "favorites").map(\.name))
            #expect(favoriteIndexes.contains("favorites_provider_updated_idx"))
        }
    }

    @Test func missingOrInaccessibleCredentialIsRecoverableWithoutSending() async throws {
        let credentials = TestProviderCredentialStore()
        let database = try testAppDatabase(credentialStore: credentials)
        let manager = ProviderManager(database: database, credentialStore: credentials)
        try manager.initialize(configurationWith(password: "initial-secret"))
        let provider = try await database.read { db in
            let provider = try Provider.where(\.isActive).fetchOne(db)
            return try #require(provider)
        }

        credentials.removePassword(for: provider.credentialReference)

        let missingCredentialManager = ProviderManager(database: database, credentialStore: credentials)
        try missingCredentialManager.loadActive()
        #expect(missingCredentialManager.hasActiveProvider)
        #expect(missingCredentialManager.session == nil)
        #expect(missingCredentialManager.accessState == .credentialsRequired)
        #expect(missingCredentialManager.requiresCredentials)
        #expect(await missingCredentialManager.runInitialSyncForActiveProvider() == .failure)

        try missingCredentialManager.update(
            provider: configurationWith(
                id: provider.id,
                endpoint: provider.endpoint,
                password: "recovered-secret"
            )
        )
        #expect(missingCredentialManager.accessState == .ready)
        #expect(credentials.storedPassword(for: provider.credentialReference) == "recovered-secret")

        credentials.failReads()
        let inaccessibleCredentialManager = ProviderManager(database: database, credentialStore: credentials)
        try inaccessibleCredentialManager.loadActive()
        #expect(inaccessibleCredentialManager.accessState == .credentialsUnavailable)
        #expect(inaccessibleCredentialManager.session == nil)
    }

    @Test func schemeLessDefaultsToHTTPSAndHTTPRequiresPersistedApproval() throws {
        let secureFields = ProviderFields(
            name: "Secure",
            endpoint: "provider.example.com/player_api.php",
            username: "user",
            password: "secret"
        )
        let secureConfiguration = try #require(secureFields.build(id: nil, kind: .xtream))
        #expect(secureConfiguration.endpoint.absoluteString == "https://provider.example.com")
        #expect(secureConfiguration.allowsInsecureHTTP == false)

        let insecureFields = ProviderFields(
            name: "Legacy HTTP",
            endpoint: "http://legacy.example.com",
            username: "user",
            password: "secret"
        )
        #expect(insecureFields.isExplicitlyInsecure)
        #expect(!insecureFields.isValid)
        #expect(insecureFields.build(id: nil, kind: .xtream) == nil)

        let rejectedCredentials = TestProviderCredentialStore()
        try withTestDatabase(credentials: rejectedCredentials) { database in
            let manager = ProviderManager(database: database, credentialStore: rejectedCredentials)
            let rejectedConfiguration = configurationWith(
                endpoint: try #require(URL(string: "http://legacy.example.com")),
                password: "must-not-send",
                allowsInsecureHTTP: false
            )

            do {
                try manager.initialize(rejectedConfiguration)
                Issue.record("Expected HTTP configuration without informed opt-in to be rejected.")
            } catch let error as ProviderManagerError {
                guard case .insecureTransportRequiresApproval = error else {
                    Issue.record("Unexpected provider error: \(error)")
                    return
                }
            }

            #expect(try database.read { try Provider.fetchCount($0) } == 0)
        }

        insecureFields.allowsInsecureHTTP = true
        let approvedConfiguration = try #require(insecureFields.build(id: nil, kind: .xtream))
        #expect(approvedConfiguration.allowsInsecureHTTP)

        let approvedCredentials = TestProviderCredentialStore()
        try withTestDatabase(credentials: approvedCredentials) { database in
            let manager = ProviderManager(database: database, credentialStore: approvedCredentials)
            try manager.initialize(approvedConfiguration)

            let storedProvider = try database.read { db in
                let provider = try Provider.where(\.isActive).fetchOne(db)
                return try #require(provider)
            }
            #expect(storedProvider.endpoint.absoluteString == "http://legacy.example.com")
            #expect(storedProvider.allowsInsecureHTTP)
            #expect(manager.accessState == .ready)
        }
    }

    @Test func persistedHTTPWithoutApprovalCannotCreateOrRunSyncSession() async throws {
        let reference = "unapproved-http-provider"
        let credentials = TestProviderCredentialStore(passwords: [reference: "must-not-send"])
        let database = try testAppDatabase(credentialStore: credentials)
        let endpoint = try #require(URL(string: "http://legacy.example.com"))

        try await database.write { db in
            try Provider.insert {
                Provider.Draft(
                    id: nil,
                    kind: .xtream,
                    name: "Unapproved HTTP",
                    username: "user",
                    credentialReference: reference,
                    endpoint: endpoint,
                    allowsInsecureHTTP: false,
                    isInitialized: false,
                    isActive: true
                )
            }.execute(db)
        }

        let manager = ProviderManager(database: database, credentialStore: credentials)
        try manager.loadActive()

        #expect(manager.accessState == .insecureTransportApprovalRequired)
        #expect(manager.session == nil)
        let result = await manager.runInitialSyncForActiveProvider()
        #expect(result == .failure)
    }

    @Test func failedDatabaseWritesCompensateKeychainChanges() throws {
        let credentials = TestProviderCredentialStore()
        try withTestDatabase(credentials: credentials) { database in
            try database.write { db in
                try #sql("""
                CREATE TRIGGER "reject_provider_insert"
                BEFORE INSERT ON "providers"
                BEGIN
                    SELECT RAISE(ABORT, 'provider insert rejected');
                END
                """).execute(db)
            }

            let manager = ProviderManager(database: database, credentialStore: credentials)
            do {
                try manager.initialize(configurationWith(password: "orphan-candidate"))
                Issue.record("Expected provider insert failure.")
            } catch {
                #expect(try database.read { try Provider.fetchCount($0) } == 0)
                #expect(credentials.storedPasswordCount == 0)
            }
        }
    }

    @Test func failedUpdateAndDeleteRestorePreviousKeychainSecret() throws {
        let credentials = TestProviderCredentialStore()
        try withTestDatabase(credentials: credentials) { database in
            let manager = ProviderManager(database: database, credentialStore: credentials)
            try manager.initialize(configurationWith(password: "original-secret"))
            let provider = try database.read { db in
                let provider = try Provider.where(\.isActive).fetchOne(db)
                return try #require(provider)
            }

            try database.write { db in
                try #sql("""
                CREATE TRIGGER "reject_provider_update"
                BEFORE UPDATE ON "providers"
                BEGIN
                    SELECT RAISE(ABORT, 'provider update rejected');
                END
                """).execute(db)
            }

            do {
                try manager.update(
                    provider: configurationWith(
                        id: provider.id,
                        endpoint: try #require(URL(string: "https://changed.example.com")),
                        password: "replacement-secret"
                    )
                )
                Issue.record("Expected provider update failure.")
            } catch {
                #expect(credentials.storedPassword(for: provider.credentialReference) == "original-secret")
                let unchangedProvider = try database.read {
                    try Provider.find($0, key: provider.id)
                }
                #expect(unchangedProvider.endpoint == provider.endpoint)
            }

            try database.write { db in
                try #sql("""
                DROP TRIGGER "reject_provider_update"
                """).execute(db)
                try #sql("""
                CREATE TRIGGER "reject_provider_delete"
                BEFORE DELETE ON "providers"
                BEGIN
                    SELECT RAISE(ABORT, 'provider delete rejected');
                END
                """).execute(db)
            }

            do {
                try manager.delete(provider: provider.id)
                Issue.record("Expected provider delete failure.")
            } catch {
                #expect(credentials.storedPassword(for: provider.credentialReference) == "original-secret")
                #expect(try database.read { try Provider.fetchCount($0) } == 1)
            }
        }
    }

    private func withTestDatabase<T>(
        credentials: TestProviderCredentialStore,
        _ operation: (any DatabaseWriter) throws -> T
    ) throws -> T {
        let database = try testAppDatabase(credentialStore: credentials)
        return try operation(database)
    }

    private func configurationWith(
        id: Provider.ID? = nil,
        endpoint: URL = URL(string: "https://example.com")!,
        password: String = "secret",
        allowsInsecureHTTP: Bool = false
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            id: id,
            kind: .xtream,
            name: "Primary",
            username: "user",
            password: password,
            endpoint: endpoint,
            allowsInsecureHTTP: allowsInsecureHTTP
        )
    }
}
