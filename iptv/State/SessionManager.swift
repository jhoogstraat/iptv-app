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
  
//    @ObservationIgnored
//    @FetchOne(Provider.where(\.isActive)) var provider
    
    // State
    var session: ActiveSession?
    
    // Helper
    var hasActiveSession: Bool { session != nil }

    func load(key _: UserDefaultKey) {
        let provider = try? database.read {
            try Provider.where { $0.isActive.eq(true) }.fetchOne($0)
        }
        guard let provider else { return }
        self.session = self.build(for: provider)
    }
    
    func initialize(_ draft: Provider.Draft) {
        var provider: Provider!
        
        try! database.write { db in
            provider = try Provider.insert { draft }.returning(\.self).fetchOne(db)!
            if let id = self.session?.provider.id {
                try Provider.find(id).update { $0.isActive = false}.execute(db)
            }
        }
        
        self.session = self.build(for: provider)
    }
    
    func change(to id: Provider.ID) throws {
        try database.write { db in
            if let id = self.session?.provider.id {
                try Provider.find(id).update { $0.isActive = false}.execute(db)
            }
            try Provider.find(id).update { $0.isActive = true }.execute(db)
        }
      
        let provider = try database.read(Provider.find(id).fetchOne)!
        
        self.session = self.build(for: provider)
    }
    
    func clear() throws {
        guard let session else { return }
        try database.write { try Provider.delete(session.provider).execute($0) }
        self.session = nil
    }
    
    private func build(for provider: Provider) -> ActiveSession? {
        let service = XtreamService(baseURL: provider.endpoint, username: provider.username, password: provider.password)
        let syncManager = SyncManager(service: service)
       
        Task {
            await syncManager.sync()
        }
        
        return ActiveSession(provider: provider, service: service, syncManager: syncManager)
    }
    
}

@Observable
class ActiveSession {
    let provider: Provider
    let service: XtreamService
    let syncManager: SyncManager
    
    init(provider: Provider, service: XtreamService, syncManager: SyncManager) {
        self.provider = provider
        self.service = service
        self.syncManager = syncManager
    }
}
