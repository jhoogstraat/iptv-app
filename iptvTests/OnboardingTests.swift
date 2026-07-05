import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import iptv

@MainActor
@Suite(.serialized)
struct OnboardingTests {
    @Test func providerFieldsBuildReturnsNilWhenRequiredFieldsAreEmpty() {
        let fields = ProviderFields(name: "", endpoint: "example.com", username: "user", password: "pass")

        #expect(fields.build(id: nil, kind: .xtream) == nil)
    }

    @Test func providerFieldsBuildNormalizesEndpointAndKind() throws {
        let cases = [
            (input: "example.com", expectedEndpoint: "http://example.com"),
            (input: "https://example.com/player_api.php", expectedEndpoint: "https://example.com"),
            (input: "https://example.com/player_api.php/player_api.php", expectedEndpoint: "https://example.com"),
        ]

        for testCase in cases {
            let fields = ProviderFields(name: " Primary ", endpoint: testCase.input, username: " user ", password: " pass ")

            let draft = try #require(fields.build(id: nil, kind: .xtream))

            #expect(draft.kind == .xtream)
            #expect(draft.endpoint.absoluteString == testCase.expectedEndpoint)
        }
    }

    @Test func requiresOnboardingWhenNoActiveProviderExists() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerManager = ProviderManager(database: database)
            try providerManager.loadActive()

            #expect(providerManager.requiresOnboarding == true)
        }
    }

    @Test func requiresOnboardingForUninitializedActiveProvider() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            try insertProvider(isInitialized: false, database: database)

            let providerManager = ProviderManager(database: database)
            try providerManager.loadActive()

            #expect(providerManager.requiresOnboarding == true)
        }
    }

    @Test func doesNotRequireOnboardingForInitializedActiveProvider() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            try insertProvider(isInitialized: true, database: database)

            let providerManager = ProviderManager(database: database)
            try providerManager.loadActive()

            #expect(providerManager.requiresOnboarding == false)
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
    private func insertProvider(isInitialized: Bool, database: any DatabaseWriter) throws -> Provider.ID {
        let endpoint = try #require(URL(string: "https://example.com"))

        return try database.write { db in
            let provider = try Provider.insert {
                Provider.Draft(
                    id: nil,
                    kind: .xtream,
                    name: "Primary",
                    username: "user",
                    password: "pass",
                    endpoint: endpoint,
                    isActive: true
                )
            }
            .returning(\.self)
            .fetchOne(db)!

            try Provider.find(provider.id).update { $0.isInitialized = #bind(isInitialized) }.execute(db)
            return provider.id
        }
    }
}
