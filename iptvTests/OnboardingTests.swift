import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import iptv

@MainActor
@Suite(.serialized)
struct OnboardingTests {
    @Test func initialMissingProviderObservationPreservesUnsavedDraft() {
        var state = OnboardingProviderRevisionState()

        #expect(state.observeMissingProvider() == false)
        #expect(state.observeMissingProvider() == true)
    }

    @Test func missingProviderAfterObservedProviderResetsDraft() {
        var state = OnboardingProviderRevisionState()

        state.observeProvider()

        #expect(state.observeMissingProvider() == true)
    }

    @Test func providerFieldsBuildReturnsNilWhenRequiredFieldsAreEmpty() {
        let fields = ProviderFields(name: "", endpoint: "example.com", username: "user", password: "pass")

        #expect(fields.build(id: nil, kind: .xtream) == nil)
    }

    @Test func providerFieldsBuildNormalizesEndpointAndKind() throws {
        let cases = [
            (input: "example.com", expectedEndpoint: "https://example.com"),
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
            let providerManager = try makeProviderManager(isInitialized: false, database: database)

            #expect(providerManager.requiresOnboarding == true)
        }
    }

    @Test func doesNotRequireOnboardingForInitializedActiveProvider() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerManager = try makeProviderManager(isInitialized: true, database: database)

            #expect(providerManager.requiresOnboarding == false)
        }
    }

    private func withTestDatabase<T>(_ operation: (any DatabaseWriter) throws -> T) throws -> T {
        let database = try testAppDatabase()
        return try operation(database)
    }

    private func resetDatabase(_ database: any DatabaseWriter) throws {
        try database.write { db in
            try Media.delete().execute(db)
            try Category.delete().execute(db)
            try Provider.delete().execute(db)
        }
    }

    private func makeProviderManager(
        isInitialized: Bool,
        database: any DatabaseWriter
    ) throws -> ProviderManager {
        let credentialStore = TestProviderCredentialStore()
        let providerManager = ProviderManager(
            database: database,
            credentialStore: credentialStore
        )
        try providerManager.initialize(
            ProviderConfiguration(
                id: nil,
                kind: .xtream,
                name: "Primary",
                username: "user",
                password: "pass",
                endpoint: try #require(URL(string: "https://example.com")),
                allowsInsecureHTTP: false
            )
        )

        if isInitialized {
            let providerID = try #require(providerManager.activeProviderID)
            try database.write { db in
                try Provider.find(providerID)
                    .update { $0.isInitialized = true }
                    .execute(db)
            }
            try providerManager.loadActive()
        }

        return providerManager
    }
}
