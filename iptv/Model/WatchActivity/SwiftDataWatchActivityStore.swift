//
//  SwiftDataWatchActivityStore.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import Foundation
import SwiftData

actor SwiftDataWatchActivityStore: WatchActivityStoring {
    private let modelContainer: ModelContainer
    private let now: @Sendable () -> Date

    init(
        modelContainer: ModelContainer,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.modelContainer = modelContainer
        self.now = now
    }

    func loadAll() async -> [WatchActivityRecord] {
        let context = ModelContext(modelContainer)
        let records = (try? context.fetch(
            FetchDescriptor<PersistedWatchActivityStoreRecord>(
                sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
            )
        )) ?? []

        return records.map {
            WatchActivityRecord(
                providerFingerprint: $0.providerFingerprint,
                videoID: $0.videoID,
                contentType: $0.contentType,
                title: $0.title,
                coverImageURL: $0.coverImageURL,
                containerExtension: $0.containerExtension,
                rating: $0.rating,
                lastPositionSeconds: $0.lastPositionSeconds,
                durationSeconds: $0.durationSeconds,
                progressFraction: $0.progressFraction,
                lastPlayedAt: $0.lastPlayedAt,
                isCompleted: $0.isCompleted
            )
        }
    }

    func recordProgress(
        input: WatchActivityInput,
        providerFingerprint: String,
        currentTime: Double,
        duration: Double?
    ) async {
        let context = ModelContext(modelContainer)
        let key = WatchActivityRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: input.contentType,
            videoID: input.videoID
        )

        let existing = ((try? context.fetch(
            FetchDescriptor<PersistedWatchActivityStoreRecord>(predicate: #Predicate { $0.id == key })
        )) ?? []).first

        let baseRecord = existing.map {
            WatchActivityRecord(
                providerFingerprint: $0.providerFingerprint,
                videoID: $0.videoID,
                contentType: $0.contentType,
                title: $0.title,
                coverImageURL: $0.coverImageURL,
                containerExtension: $0.containerExtension,
                rating: $0.rating,
                lastPositionSeconds: $0.lastPositionSeconds,
                durationSeconds: $0.durationSeconds,
                progressFraction: $0.progressFraction,
                lastPlayedAt: $0.lastPlayedAt,
                isCompleted: $0.isCompleted
            )
        } ?? WatchActivityRecord.from(input: input, providerFingerprint: providerFingerprint, now: now())

        let updated = baseRecord.updatingProgress(currentTime: currentTime, duration: duration, now: now())

        if let existing {
            context.delete(existing)
        }
        context.insert(Self.entity(from: updated))
        try? context.save()
    }

    func markCompleted(input: WatchActivityInput, providerFingerprint: String) async {
        let context = ModelContext(modelContainer)
        let key = WatchActivityRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: input.contentType,
            videoID: input.videoID
        )

        let existing = ((try? context.fetch(
            FetchDescriptor<PersistedWatchActivityStoreRecord>(predicate: #Predicate { $0.id == key })
        )) ?? []).first

        let baseRecord = existing.map {
            WatchActivityRecord(
                providerFingerprint: $0.providerFingerprint,
                videoID: $0.videoID,
                contentType: $0.contentType,
                title: $0.title,
                coverImageURL: $0.coverImageURL,
                containerExtension: $0.containerExtension,
                rating: $0.rating,
                lastPositionSeconds: $0.lastPositionSeconds,
                durationSeconds: $0.durationSeconds,
                progressFraction: $0.progressFraction,
                lastPlayedAt: $0.lastPlayedAt,
                isCompleted: $0.isCompleted
            )
        } ?? WatchActivityRecord.from(input: input, providerFingerprint: providerFingerprint, now: now())

        if let existing {
            context.delete(existing)
        }
        context.insert(Self.entity(from: baseRecord.markingCompleted(now: now())))
        try? context.save()
    }

    func clear(for providerFingerprint: String) async {
        let context = ModelContext(modelContainer)
        let matches = (try? context.fetch(
            FetchDescriptor<PersistedWatchActivityStoreRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )) ?? []
        for match in matches {
            context.delete(match)
        }
        try? context.save()
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
