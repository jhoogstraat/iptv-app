//
//  Session.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 25.03.26.
//

import SwiftUI
import SQLiteData
import Dependencies

@MainActor
@Observable
final class Session {
   
    // MARK: - Dependencies
    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database
   
    private let syncManager: SyncManager
    
    // MARK: - State
    var providerID: Provider.ID
    
   // MARK: - Init
    init(syncManager: SyncManager, providerID: Provider.ID) {
        self.syncManager = syncManager
        self.providerID = providerID
    }
    
    // MARK: - Helper
    var provider: Provider {
        return try! database.read { try Provider.find($0, key: providerID) }
    }
    
    var sync: SyncManager.SyncStatus {
        if syncManager.movieSync == .active || syncManager.seriesSync == .active { return .active }
        if syncManager.movieSync == .success && syncManager.seriesSync == .success { return .success }
        if syncManager.movieSync == .failure || syncManager.seriesSync == .failure { return .failure }
        return .idle
    }
   
    // MARK: - Methods
    func update(_ type: MediaType, in category: Category.ID) async throws {
        switch type {
            case .movie:
                try await self.syncManager.updateMovies(in: category)
            case .series:
                try await self.syncManager.updateSeries(in: category)
            case .episode: break
        }
    }
}

extension Session: Equatable {
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.providerID == rhs.providerID
    }
}
