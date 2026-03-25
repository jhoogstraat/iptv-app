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
    @Dependency(\.defaultDatabase) var database

    // MARK: - State
    private(set) var session: Session?
    
    // MARK: - Helper
    var hasActiveProvider: Bool { session != nil }
    
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
            try Provider.upsert { provider }.returning(\.id).fetchOne(db)!
        }

        setState(id)
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

            let service = XtreamService(baseURL: provider.endpoint, username: provider.username, password: provider.password)
            let syncManager = SyncManager(service: service)
            
            self.session = Session(syncManager: syncManager, providerID: provider.id)
          
            if !provider.isInitialized {
                _ = initalizeLibrary(of: provider.id, syncManager)
            }
        } catch {
            // FIXME: Handle error better for user
            clearState()
            logger.warning("Failed to reload provider state: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func initalizeLibrary(of id: Provider.ID, _ syncManager: SyncManager) -> Task<Void, Error> {
        Task {
            guard await syncManager.sync(provider: id) == .success else { return }
            try await self.database.write { db in
                try Provider.find(id).update { $0.isInitialized = true }.execute(db)
            }
        }
    }
    
    private func clearState() {
        session = nil
    }

    private func clearLibrary(of id: Provider.ID) throws {
        try database.write { db in
            try Media.delete().execute(db)
            try Category.delete().execute(db)
        }
    }
}

private let logger = Logger(subsystem: "IPTV", category: "SessionManager")
