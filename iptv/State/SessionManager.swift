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
final class SessionManager {
    enum ProviderState {
        case provider(ActiveSession)
        case noProvider
    }

    // Deps
    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database

    // State
    private(set) var providerState: ProviderState = .noProvider

    // Helper
    var session: ActiveSession? {
        if case .provider(let session) = providerState {
            session
        } else {
            nil
        }
    }

    var hasActiveSession: Bool { session != nil }

    func load() {
        reloadProviderState()
    }
    
    func initialize(_ draft: Provider.Draft) throws {
        try database.write { db in
            if let id = self.session?.provider {
                try Provider.find(id).update { $0.isActive = false }.execute(db)
            }

            _ = try Provider.insert { draft }.returning(\.self).fetchOne(db)
        }

        reloadProviderState()
    }
    
    func change(to id: Provider.ID) throws {
        try database.write { db in
            if let id = self.session?.provider {
                try Provider.find(id).update { $0.isActive = false }.execute(db)
            }
            try Provider.find(id).update { $0.isActive = true }.execute(db)
        }

        reloadProviderState()
    }
    
    func upsert(provider: Provider.Draft) throws {
        try database.write { db in
            try Provider.upsert { provider }.execute(db)
        }

        reloadProviderState()
    }

    func clear() throws {
        guard let session else { return }
        try database.write { db in
            try Provider.find(session.provider).delete().execute(db)
            try Media.delete().execute(db)
            try Category.delete().execute(db)
        }
        providerState = .noProvider
    }
    
    private func reloadProviderState() {
        do {
            let provider = try database.read {
                try Provider.where { $0.isActive.eq(true) }.fetchOne($0)
            }

            guard let provider else {
                clearLibraryIfNeeded()
                providerState = .noProvider
                return
            }

            providerState = .provider(build(for: provider))
        } catch {
            clearLibraryIfNeeded()
            providerState = .noProvider
            sessionManagerLogger.warning("Failed to reload provider state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearLibraryIfNeeded() {
        do {
            try database.write { db in
                try Media.delete().execute(db)
                try Category.delete().execute(db)
            }
        } catch {
            sessionManagerLogger.warning("Failed to clear library without an active provider: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func build(for provider: Provider) -> ActiveSession {
        let service = XtreamService(baseURL: provider.endpoint, username: provider.username, password: provider.password)
        let syncManager = SyncManager(service: service)
      
        if !provider.isInitialized {
            let id = provider.id
            Task {
                await syncManager.sync()
                try? await self.database.write { db in
                    try Provider.find(id).update { $0.isInitialized = true }.execute(db)
                }
            }
        }
        
        return ActiveSession(provider: provider.id, service: service, syncManager: syncManager)
    }
    
}

@Observable
final class ActiveSession {
    let provider: Provider.ID
    let service: XtreamService
    let syncManager: SyncManager
    
    init(provider: Provider.ID, service: XtreamService, syncManager: SyncManager) {
        self.provider = provider
        self.service = service
        self.syncManager = syncManager
    }
}

private let sessionManagerLogger = Logger(subsystem: "IPTV", category: "SessionManager")
