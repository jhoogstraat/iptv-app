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
        if syncManager.movieSync == .active || syncManager.seriesSync == .active || syncManager.liveSync == .active { return .active }
        if syncManager.movieSync == .success && syncManager.seriesSync == .success && syncManager.liveSync == .success { return .success }
        if syncManager.movieSync == .failure || syncManager.seriesSync == .failure || syncManager.liveSync == .failure { return .failure }
        return .idle
    }
    
    var initialSyncPhase: SyncManager.InitialSyncPhase { syncManager.initialSyncPhase }
    var syncErrorMessage: String? { syncManager.lastErrorMessage }
    var movieSyncStatus: SyncManager.SyncStatus { syncManager.movieSync }
    var seriesSyncStatus: SyncManager.SyncStatus { syncManager.seriesSync }
    var liveSyncStatus: SyncManager.SyncStatus { syncManager.liveSync }
    func hydrationState(for category: Category) -> SyncManager.CategoryHydrationState {
        if let state = syncManager.categoryHydrationStates[category.id] {
            return state
        }

        guard category.updatedAt != nil else { return .unhydrated }

        do {
            let count = try database.read { db in
                try Media.where { $0.categoryID.eq(category.id) }.fetchCount(db)
            }
            return count == 0 ? .empty : .populated(count)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
   
   
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
            case .live:
                try await self.syncManager.updateLiveChannels(in: category)
            case .episode:
                break
        }
    }

    func enrichDetails(for media: Media) async throws {
        try await syncManager.enrichDetails(for: media.id)
    }
}

extension Session: Equatable {
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.providerID == rhs.providerID
    }
}
