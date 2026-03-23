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

@Observable
class SessionManager {
    // Deps
    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database
    
    @ObservationIgnored
    @FetchOne(Provider.where(\.isActive)) var provider
    
    // State
    var session: ActiveSession?
    
    // Helper
    var hasActiveSession: Bool { session != nil }

    func load() {
        let provider = try? database.read {
            try Provider.where { $0.isActive.eq(true) }.fetchOne($0)
        }
        guard let provider else { return }
        self.session = self.build(for: provider)
    }
    
    func initialize(_ draft: Provider.Draft) throws {
        var provider: Provider!
        try database.write { db in
            provider = try Provider.insert { draft }.returning(\.self).fetchOne(db)!
            
            if let id = self.session?.provider {
                try Provider.find(id).update { $0.isActive = false}.execute(db)
            }
        }
        
        self.session = self.build(for: provider)
    }
    
    func change(to id: Provider.ID) throws {
        try database.write { db in
            if let id = self.session?.provider {
                try Provider.find(id).update { $0.isActive = false }.execute(db)
            }
            try Provider.find(id).update { $0.isActive = true }.execute(db)
        }
      
        let provider = try database.read { try Provider.find($0, key: id) }
        
        self.session = self.build(for: provider)
    }
    
    func upsert(provider: Provider.Draft) throws {
        try database.write { db in
            try Provider.upsert { provider }.execute(db)
        }
    }

    func clear() throws {
        guard let session else { return }
        try database.write { try Provider.find(session.provider).delete().execute($0) }
        self.session = nil
    }
    
    private func build(for provider: Provider) -> ActiveSession? {
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
class ActiveSession {
    let provider: Provider.ID
    let service: XtreamService
    let syncManager: SyncManager
    
    init(provider: Provider.ID, service: XtreamService, syncManager: SyncManager) {
        self.provider = provider
        self.service = service
        self.syncManager = syncManager
    }
}
