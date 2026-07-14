//
//  SessionManager.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 17.03.26.
//

import SwiftUI
import OSLog
import xtream_swift
import Dependencies
import SQLiteData

@MainActor
@Observable
final class ProviderManager {
    enum ProviderAccessState: Equatable {
        case noProvider
        case ready
        case credentialsRequired
        case credentialsUnavailable
        case insecureTransportApprovalRequired
    }
    enum ProviderUpdateTransition: Equatable {
        case unchanged
        case nameOnly
        case connectionChanged
    }


    // MARK: - Deps
    @ObservationIgnored
    private let database: any DatabaseWriter
    @ObservationIgnored
    private let credentialStore: any ProviderCredentialStoring

    // MARK: - State
    private(set) var session: Session?
    private(set) var activeProviderID: Provider.ID?
    private(set) var activeProviderIsInitialized = false
    private(set) var accessState: ProviderAccessState = .noProvider
    private(set) var revision = 0

    // MARK: - Helper
    var hasActiveProvider: Bool { activeProviderID != nil }
    var requiresCredentials: Bool {
        accessState == .credentialsRequired || accessState == .credentialsUnavailable
    }
    var requiresOnboarding: Bool {
        accessState != .ready || !activeProviderIsInitialized
    }

    init(
        database: (any DatabaseWriter)? = nil,
        credentialStore: any ProviderCredentialStoring = KeychainProviderCredentialStore()
    ) {
        @Dependency(\.defaultDatabase) var defaultDatabase
        self.database = database ?? defaultDatabase
        self.credentialStore = credentialStore
    }

    // MARK: - Public
    func loadActive() throws {
        guard let activeProvider = try database.read({
            try Provider.where(\.isActive).fetchOne($0)
        }) else {
            clearState()
            revision += 1
            return
        }

        setState(activeProvider)
        revision += 1
    }

    func initialize(_ configuration: ProviderConfiguration) throws {
        try validate(configuration)
        let credentialReference = ProviderCredentialReference.make()
        let previousProviderID = activeProviderID

        try credentialStore.setPassword(configuration.password, for: credentialReference)
        session?.invalidate()

        let id: Int
        do {
            id = try database.write { db in
                if let previousProviderID {
                    try Provider.find(previousProviderID).update { $0.isActive = false }.execute(db)
                }
                try Media.delete().execute(db)
                try Category.delete().execute(db)

                let insertedProvider = try Provider.insert {
                    Provider.Draft(
                        id: nil,
                        kind: configuration.kind,
                        name: configuration.name,
                        username: configuration.username,
                        credentialReference: credentialReference,
                        endpoint: configuration.endpoint,
                        allowsInsecureHTTP: configuration.allowsInsecureHTTP,
                        isInitialized: false,
                        isActive: true
                    )
                }
                .returning(\.self)
                .fetchOne(db)!
                return insertedProvider.id
            }
        } catch {
            if let previousProviderID {
                try? setState(previousProviderID)
            }
            try compensateCredential(
                after: error,
                operation: "creating provider",
                reference: credentialReference
            ) {
                try credentialStore.deletePassword(for: credentialReference)
            }
        }

        try setState(id)
        revision += 1
    }

    func change(to id: Provider.ID) throws {
        let previousProviderID = activeProviderID
        guard previousProviderID != id else { return }

        session?.invalidate()
        do {
            try database.write { db in
                if let previousProviderID {
                    try Provider.find(previousProviderID).update { $0.isActive = false }.execute(db)
                }

                try Media.delete().execute(db)
                try Category.delete().execute(db)
                try Provider.find(id).update {
                    $0.isActive = true
                    $0.isInitialized = false
                }.execute(db)
            }
        } catch {
            if let previousProviderID {
                try? setState(previousProviderID)
            }
            throw error
        }

        try setState(id)
        revision += 1
    }

    @discardableResult
    func update(
        provider configuration: ProviderConfiguration,
        expectedRevision: Int? = nil
    ) throws -> ProviderUpdateTransition {
        try validate(configuration)
        if let expectedRevision, expectedRevision != revision {
            throw ProviderManagerError.staleProviderRevision(
                expected: expectedRevision,
                actual: revision
            )
        }
        guard let id = configuration.id else {
            throw ProviderManagerError.missingProviderIdentity
        }

        let existing = try database.read { try Provider.find($0, key: id) }
        guard !existing.credentialReference.isEmpty else {
            throw ProviderManagerError.missingCredentialReference
        }

        let previousPassword = try credentialStore.password(for: existing.credentialReference)
        let credentialChanged = previousPassword != configuration.password
        let requiresActivation = activeProviderID != id || !existing.isActive
        let connectionChanged =
            existing.kind != configuration.kind
            || existing.username != configuration.username
            || existing.endpoint != configuration.endpoint
            || existing.allowsInsecureHTTP != configuration.allowsInsecureHTTP
            || credentialChanged
            || requiresActivation
        let nameChanged = existing.name != configuration.name

        guard connectionChanged || nameChanged else {
            return .unchanged
        }

        if !connectionChanged {
            try database.write { db in
                try Provider.find(id).update {
                    $0.name = #bind(configuration.name)
                }.execute(db)
            }
            revision += 1
            return .nameOnly
        }

        if credentialChanged {
            try credentialStore.setPassword(
                configuration.password,
                for: existing.credentialReference
            )
        }
        session?.invalidate()

        do {
            try database.write { db in
                if let activeProviderID, activeProviderID != id {
                    try Provider.find(activeProviderID).update { $0.isActive = false }.execute(db)
                }

                try Provider.upsert {
                    Provider.Draft(
                        id: id,
                        kind: configuration.kind,
                        name: configuration.name,
                        username: configuration.username,
                        credentialReference: existing.credentialReference,
                        endpoint: configuration.endpoint,
                        allowsInsecureHTTP: configuration.allowsInsecureHTTP,
                        isInitialized: false,
                        isActive: true
                    )
                }.execute(db)

                try Media.delete().execute(db)
                try Category.delete().execute(db)
            }
        } catch {
            setState(existing, password: previousPassword)
            guard credentialChanged else { throw error }
            let databaseError = error
            try compensateCredential(
                after: databaseError,
                operation: "updating provider",
                reference: existing.credentialReference
            ) {
                if let previousPassword {
                    try credentialStore.setPassword(
                        previousPassword,
                        for: existing.credentialReference
                    )
                } else {
                    try credentialStore.deletePassword(for: existing.credentialReference)
                }
            }
        }

        try setState(id)
        revision += 1
        return .connectionChanged
    }

    func activeProviderConfiguration() throws -> ProviderConfiguration? {
        guard let activeProviderID else { return nil }
        let provider = try database.read {
            try Provider.find($0, key: activeProviderID)
        }
        let password: String
        if provider.credentialReference.isEmpty {
            password = ""
        } else {
            do {
                password = try credentialStore.password(for: provider.credentialReference) ?? ""
            } catch {
                password = ""
                logger.warning("Provider password is unavailable while preparing editable configuration: \(error.localizedDescription, privacy: .public)")
            }
        }

        return ProviderConfiguration(
            id: provider.id,
            kind: provider.kind,
            name: provider.name,
            username: provider.username,
            password: password,
            endpoint: provider.endpoint,
            allowsInsecureHTTP: provider.allowsInsecureHTTP
        )
    }

    @discardableResult
    func runInitialSyncForActiveProvider() async -> SyncManager.SyncStatus {
        await synchronizeActiveProvider(force: false)
    }

    @discardableResult
    func resyncActiveProvider() async -> SyncManager.SyncStatus {
        await synchronizeActiveProvider(force: true)
    }

    private func synchronizeActiveProvider(force: Bool) async -> SyncManager.SyncStatus {
        guard accessState == .ready, let capturedSession = session else { return .failure }
        guard force || !activeProviderIsInitialized else { return .success }

        let providerID = capturedSession.providerID
        let result = await capturedSession.runInitialSync()
        guard result == .success else { return result }
        guard session === capturedSession, capturedSession.isCurrent else { return .idle }

        do {
            let committed = try await database.write { db in
                guard try Provider.where(\.isActive).fetchOne(db)?.id == providerID else {
                    return false
                }

                try Provider.find(providerID).update { $0.isInitialized = true }.execute(db)
                return true
            }
            guard committed, session === capturedSession, capturedSession.isCurrent else {
                return .idle
            }
            activeProviderIsInitialized = true
            return .success
        } catch is CancellationError {
            return .idle
        } catch {
            logger.warning("Failed to commit provider sync: \(error.localizedDescription, privacy: .public)")
            return .failure
        }
    }

    func delete(provider id: Provider.ID) throws {
        let provider = try database.read { try Provider.find($0, key: id) }
        let reference = provider.credentialReference
        let previousPassword = reference.isEmpty
            ? nil
            : try credentialStore.password(for: reference)
        let isDeletingActiveProvider = activeProviderID == id

        if !reference.isEmpty {
            try credentialStore.deletePassword(for: reference)
        }
        if isDeletingActiveProvider {
            session?.invalidate()
        }

        do {
            try database.write { db in
                try WatchActivityStore.deleteActivity(for: id, in: db)
                try FavoriteStore.deleteFavorites(for: id, in: db)
                if isDeletingActiveProvider {
                    try Media.delete().execute(db)
                    try Category.delete().execute(db)
                }
                try Provider.find(id).delete().execute(db)
            }
        } catch {
            if isDeletingActiveProvider {
                setState(provider, password: previousPassword)
            }
            guard let previousPassword, !reference.isEmpty else { throw error }
            let databaseError = error
            try compensateCredential(
                after: databaseError,
                operation: "deleting provider",
                reference: reference
            ) {
                try credentialStore.setPassword(previousPassword, for: reference)
            }
        }

        if isDeletingActiveProvider {
            clearState()
        }
        revision += 1
    }

    // MARK: - Private
    private func setState(_ providerID: Provider.ID) throws {
        let provider = try database.read {
            try Provider.find($0, key: providerID)
        }
        setState(provider)
    }

    private func setState(_ provider: Provider, password suppliedPassword: String? = nil) {
        session?.invalidate()
        session = nil
        activeProviderID = provider.id
        activeProviderIsInitialized = provider.isInitialized

        guard isTransportAllowed(for: provider) else {
            accessState = .insecureTransportApprovalRequired
            return
        }

        let password: String
        if let suppliedPassword {
            password = suppliedPassword
        } else {
            do {
                guard !provider.credentialReference.isEmpty,
                      let storedPassword = try credentialStore.password(
                        for: provider.credentialReference
                      ),
                      !storedPassword.isEmpty
                else {
                    accessState = .credentialsRequired
                    return
                }
                password = storedPassword
            } catch {
                accessState = .credentialsUnavailable
                logger.warning("Provider credentials are inaccessible: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        let service: XtreamService
        switch provider.kind {
            case .xtream:
                service = XtreamService(
                    baseURL: provider.endpoint,
                    username: provider.username,
                    password: password
                )
        }
        let syncManager = SyncManager(
            service: service,
            providerID: provider.id,
            providerEndpoint: provider.endpoint,
            username: provider.username,
            password: password,
            database: database
        )

        session = Session(
            syncManager: syncManager,
            providerID: provider.id,
            database: database
        )
        accessState = .ready
    }

    private func validate(_ configuration: ProviderConfiguration) throws {
        guard !configuration.name.isEmpty,
              !configuration.username.isEmpty,
              !configuration.password.isEmpty
        else {
            throw ProviderManagerError.incompleteConfiguration
        }

        let scheme = configuration.endpoint.scheme?.lowercased()
        guard scheme == "https" || scheme == "http",
              configuration.endpoint.user == nil,
              configuration.endpoint.password == nil
        else {
            throw ProviderManagerError.unsupportedEndpoint
        }

        guard scheme != "http" || configuration.allowsInsecureHTTP else {
            throw ProviderManagerError.insecureTransportRequiresApproval
        }
    }

    private func isTransportAllowed(for provider: Provider) -> Bool {
        switch provider.endpoint.scheme?.lowercased() {
            case "https":
                true
            case "http":
                provider.allowsInsecureHTTP
            default:
                false
        }
    }

    private func compensateCredential(
        after primaryError: Error,
        operation: String,
        reference: String,
        _ rollback: () throws -> Void
    ) throws -> Never {
        do {
            try rollback()
        } catch {
            throw ProviderManagerError.credentialRollbackFailed(
                operation: operation,
                reference: reference,
                primaryError: primaryError.localizedDescription,
                rollbackError: error.localizedDescription
            )
        }
        throw primaryError
    }

    private func clearState() {
        session?.invalidate()
        session = nil
        activeProviderID = nil
        activeProviderIsInitialized = false
        accessState = .noProvider
    }
}

enum ProviderManagerError: Error, LocalizedError {
    case incompleteConfiguration
    case missingProviderIdentity
    case missingCredentialReference
    case unsupportedEndpoint
    case insecureTransportRequiresApproval
    case staleProviderRevision(expected: Int, actual: Int)
    case credentialRollbackFailed(
        operation: String,
        reference: String,
        primaryError: String,
        rollbackError: String
    )

    var errorDescription: String? {
        switch self {
            case .incompleteConfiguration:
                "Please complete all provider fields."
            case .missingProviderIdentity:
                "The provider could not be updated because its identity is missing."
            case .missingCredentialReference:
                "The provider needs its password entered again before it can be updated."
            case .unsupportedEndpoint:
                "Enter an HTTP or HTTPS provider URL without embedded credentials."
            case .insecureTransportRequiresApproval:
                "HTTP sends credentials without encryption. Explicitly allow insecure HTTP to continue."
            case let .staleProviderRevision(expected, actual):
                "Provider settings changed in another window (expected revision \(expected), current revision \(actual)). Review the refreshed values and save again."
            case let .credentialRollbackFailed(operation, reference, primaryError, rollbackError):
                "Failed while \(operation), and credential rollback also failed for \(reference). Original error: \(primaryError). Rollback error: \(rollbackError)."
        }
    }
}

private let logger = Logger(subsystem: "IPTV", category: "SessionManager")
