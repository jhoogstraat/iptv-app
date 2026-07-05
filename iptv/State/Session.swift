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
    private let database: any DatabaseWriter
   
    private let syncManager: SyncManager
    
    // MARK: - State
    var providerID: Provider.ID
    
   // MARK: - Init
    init(syncManager: SyncManager, providerID: Provider.ID, database: (any DatabaseWriter)? = nil) {
        @Dependency(\.defaultDatabase) var defaultDatabase
        self.syncManager = syncManager
        self.providerID = providerID
        self.database = database ?? defaultDatabase
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
    
    var initialSyncPhase: SyncManager.InitialSyncPhase { syncManager.initialSyncPhase }
    var syncErrorMessage: String? { syncManager.lastErrorMessage }
    var movieSyncStatus: SyncManager.SyncStatus { syncManager.movieSync }
    var seriesSyncStatus: SyncManager.SyncStatus { syncManager.seriesSync }
   
    // MARK: - Methods
    @discardableResult
    func runInitialSync() async -> SyncManager.SyncStatus {
        await syncManager.sync(provider: providerID)
    }
    
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
