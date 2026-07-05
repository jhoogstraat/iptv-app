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
    
    // MARK: - Deps
    @ObservationIgnored
    private let database: any DatabaseWriter

    // MARK: - State
    private(set) var session: Session?
    private(set) var activeProviderIsInitialized = false
    
    // MARK: - Helper
    var hasActiveProvider: Bool { session != nil }
    var requiresOnboarding: Bool { session == nil || !activeProviderIsInitialized }
    
    init(database: (any DatabaseWriter)? = nil) {
        @Dependency(\.defaultDatabase) var defaultDatabase
        self.database = database ?? defaultDatabase
    }
    
    // MARK: - Public
    func loadActive() throws {
        let activeProvider = try database.read {
            try Provider.where(\.isActive).fetchOne($0)
        }
        
        guard let activeProvider else {
            return
        }
        
        setState(activeProvider.id)
    }
    
    func initialize(_ draft: Provider.Draft) throws {
        let id = try database.write { db in
            if let id = session?.providerID {
                try Provider.find(id).update { $0.isActive = false }.execute(db)
            }
            return try Provider.insert { draft }.returning(\.id).fetchOne(db)!
        }

        setState(id)
    }
    
    func change(to id: Provider.ID) throws {
        try database.write { db in
            if let active = session?.providerID {
                try Provider.find(active).update { $0.isActive = false }.execute(db)
            }
            try Provider.find(id).update { $0.isActive = true }.execute(db)
        }

        setState(id)
    }
    
    func update(provider: Provider.Draft) throws {
        let id = try database.write { db in
            let id = try Provider.upsert { provider }.returning(\.id).fetchOne(db)!
            try Provider.find(id).update {
                $0.isInitialized = false
                $0.isActive = true
            }.execute(db)
            return id
        }

        setState(id)
    }

    @discardableResult
    func runInitialSyncForActiveProvider() async -> SyncManager.SyncStatus {
        guard let session else { return .failure }
        guard !activeProviderIsInitialized else { return .success }

        let providerID = session.providerID
        let result = await session.runInitialSync()
        if result == .success {
            do {
                try await database.write { db in
                    try Provider.find(providerID).update { $0.isInitialized = true }.execute(db)
                }
                activeProviderIsInitialized = true
            } catch {
                logger.warning("Failed to mark provider initialized: \(error.localizedDescription, privacy: .public)")
                return .failure
            }
        }

        return result
    }

    func delete(provider id: Provider.ID) throws {
        clearState()
        
        try database.write { db in
            try Provider.find(id).delete().execute(db)
        }
        
        try clearLibrary(of: id)
    }
   
    // MARK: - Private
    private func setState(_ providerID: Provider.ID) {
        do {
            let provider = try database.read {
                try Provider.find($0, key: providerID)
            }

            let service: XtreamService
            switch provider.kind {
                case .xtream:
                    service = XtreamService(baseURL: provider.endpoint, username: provider.username, password: provider.password)
            }
            let syncManager = SyncManager(service: service, database: database)
            
            self.session = Session(syncManager: syncManager, providerID: provider.id, database: database)
            self.activeProviderIsInitialized = provider.isInitialized
        } catch {
            // FIXME: Handle error better for user
            clearState()
            logger.warning("Failed to reload provider state: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    
    private func clearState() {
        session = nil
        activeProviderIsInitialized = false
    }

    private func clearLibrary(of id: Provider.ID) throws {
        try database.write { db in
            try Media.delete().execute(db)
            try Category.delete().execute(db)
        }
    }
}

private let logger = Logger(subsystem: "IPTV", category: "SessionManager")
