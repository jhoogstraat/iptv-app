//
//  WatchActivityStore.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import Foundation
import OSLog
import SwiftData

@ModelActor
actor WatchActivityStore {
    nonisolated private static let log = Logger(subsystem: "iptv", category: "WatchActivityStore")
    private var now: @Sendable () -> Date = Date.init

    init(
        modelContainer: ModelContainer,
        now: @escaping @Sendable () -> Date
    ) {
        let modelContext = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
        self.now = now
    }

    func loadAll() async -> [WatchActivityRecord] {
        do {
            return try records(
                matching: nil,
                sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
            )
        } catch {
            Self.log.error("Failed to load watch activity: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func load(providerFingerprint: String) async -> [WatchActivityRecord] {
        do {
            return try records(
                matching: #Predicate { $0.providerFingerprint == providerFingerprint },
                sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
            )
        } catch {
            Self.log.error("Failed to load watch activity for provider: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func load(providerFingerprint: String, contentType: String) async -> [WatchActivityRecord] {
        do {
            return try records(
                matching: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.contentType == contentType
                },
                sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
            )
        } catch {
            Self.log.error("Failed to load scoped watch activity: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func recordProgress(
        input: WatchActivityInput,
        providerFingerprint: String,
        currentTime: Double,
        duration: Double?
    ) async {
        do {
            let baseRecord = try existingRecord(
                providerFingerprint: providerFingerprint,
                contentType: input.contentType,
                videoID: input.videoID
            ) ?? WatchActivityRecord.from(input: input, providerFingerprint: providerFingerprint, now: now())
            let updated = baseRecord.updatingProgress(currentTime: currentTime, duration: duration, now: now())
            try upsert(updated)
        } catch {
            Self.log.error("Failed to record watch progress: \(error.localizedDescription, privacy: .public)")
        }
    }

    func markCompleted(input: WatchActivityInput, providerFingerprint: String) async {
        do {
            let baseRecord = try existingRecord(
                providerFingerprint: providerFingerprint,
                contentType: input.contentType,
                videoID: input.videoID
            ) ?? WatchActivityRecord.from(input: input, providerFingerprint: providerFingerprint, now: now())
            try upsert(baseRecord.markingCompleted(now: now()))
        } catch {
            Self.log.error("Failed to mark watch activity as completed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clear(for providerFingerprint: String) async {
        do {
            try modelContext.delete(
                model: PersistedWatchActivityStoreRecord.self,
                where: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
            try modelContext.save()
        } catch {
            Self.log.error("Failed to clear watch activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func records(
        matching predicate: Predicate<PersistedWatchActivityStoreRecord>?,
        sortBy: [SortDescriptor<PersistedWatchActivityStoreRecord>] = []
    ) throws -> [WatchActivityRecord] {
        let descriptor = FetchDescriptor<PersistedWatchActivityStoreRecord>(
            predicate: predicate,
            sortBy: sortBy
        )
        return try modelContext.fetch(descriptor).map(Self.record(from:))
    }

    private func existingRecord(
        providerFingerprint: String,
        contentType: String,
        videoID: Int
    ) throws -> WatchActivityRecord? {
        let key = WatchActivityRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            videoID: videoID
        )
        let descriptor = FetchDescriptor<PersistedWatchActivityStoreRecord>(
            predicate: #Predicate { $0.id == key }
        )
        return try modelContext.fetch(descriptor).first.map(Self.record(from:))
    }

    private func upsert(_ record: WatchActivityRecord) throws {
        modelContext.insert(Self.entity(from: record))
        try modelContext.save()
    }

    private static func record(from entity: PersistedWatchActivityStoreRecord) -> WatchActivityRecord {
        WatchActivityRecord(
            providerFingerprint: entity.providerFingerprint,
            videoID: entity.videoID,
            contentType: entity.contentType,
            title: entity.title,
            coverImageURL: entity.coverImageURL,
            containerExtension: entity.containerExtension,
            rating: entity.rating,
            lastPositionSeconds: entity.lastPositionSeconds,
            durationSeconds: entity.durationSeconds,
            progressFraction: entity.progressFraction,
            lastPlayedAt: entity.lastPlayedAt,
            isCompleted: entity.isCompleted
        )
    }

    private static func entity(from record: WatchActivityRecord) -> PersistedWatchActivityStoreRecord {
        PersistedWatchActivityStoreRecord(
            id: record.key,
            providerFingerprint: record.providerFingerprint,
            videoID: record.videoID,
            contentType: record.contentType,
            title: record.title,
            coverImageURL: record.coverImageURL,
            containerExtension: record.containerExtension,
            rating: record.rating,
            lastPositionSeconds: record.lastPositionSeconds,
            durationSeconds: record.durationSeconds,
            progressFraction: record.progressFraction,
            lastPlayedAt: record.lastPlayedAt,
            isCompleted: record.isCompleted
        )
    }
}
