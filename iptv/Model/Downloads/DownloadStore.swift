//
//  DownloadStore.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation
import OSLog
import SwiftData

private struct DownloadStoreSnapshot: Codable {
    let groups: [DownloadGroupRecord]
    let assets: [DownloadAssetRecord]
}

private protocol DownloadStorePersistence: Sendable {
    func load() async throws -> DownloadStoreSnapshot?
    func save(_ snapshot: DownloadStoreSnapshot) async throws
}

private actor FileDownloadStorePersistence: DownloadStorePersistence {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() async throws -> DownloadStoreSnapshot? {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryURL.path()) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(DownloadStoreSnapshot.self, from: data)
    }

    func save(_ snapshot: DownloadStoreSnapshot) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryURL.path()) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private actor SwiftDataDownloadStorePersistence: DownloadStorePersistence {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func load() async throws -> DownloadStoreSnapshot? {
        let context = ModelContext(modelContainer)
        let groups = try context.fetch(
            FetchDescriptor<PersistedDownloadGroupStoreRecord>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        ).compactMap(Self.groupRecord(from:))

        let assets = try context.fetch(
            FetchDescriptor<PersistedDownloadAssetStoreRecord>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        ).compactMap(Self.assetRecord(from:))

        guard !groups.isEmpty || !assets.isEmpty else { return nil }
        return DownloadStoreSnapshot(groups: groups, assets: assets)
    }

    func save(_ snapshot: DownloadStoreSnapshot) async throws {
        let context = ModelContext(modelContainer)
        for record in try context.fetch(FetchDescriptor<PersistedDownloadGroupStoreRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<PersistedDownloadAssetStoreRecord>()) {
            context.delete(record)
        }

        for group in snapshot.groups {
            context.insert(
                PersistedDownloadGroupStoreRecord(
                    id: group.id,
                    scopeProfileID: group.scope.profileID,
                    scopeProviderFingerprint: group.scope.providerFingerprint,
                    kind: group.kind.rawValue,
                    title: group.title,
                    parentVideoID: group.parentVideoID,
                    contentType: group.contentType,
                    coverImageURL: group.coverImageURL,
                    childAssetIDs: group.childAssetIDs,
                    status: group.status.rawValue,
                    completedAssetCount: group.completedAssetCount,
                    totalAssetCount: group.totalAssetCount,
                    bytesWritten: group.bytesWritten,
                    expectedBytes: group.expectedBytes,
                    createdAt: group.createdAt,
                    updatedAt: group.updatedAt
                )
            )
        }

        for asset in snapshot.assets {
            context.insert(
                PersistedDownloadAssetStoreRecord(
                    id: asset.id,
                    scopeProfileID: asset.scope.profileID,
                    scopeProviderFingerprint: asset.scope.providerFingerprint,
                    videoID: asset.videoID,
                    contentType: asset.contentType,
                    title: asset.title,
                    coverImageURL: asset.coverImageURL,
                    containerExtension: asset.containerExtension,
                    seriesID: asset.seriesID,
                    seasonNumber: asset.seasonNumber,
                    remoteURL: asset.remoteURL.absoluteString,
                    localURL: asset.localURL?.absoluteString,
                    resumeDataURL: asset.resumeDataURL?.absoluteString,
                    status: asset.status.rawValue,
                    bytesWritten: asset.bytesWritten,
                    expectedBytes: asset.expectedBytes,
                    attemptCount: asset.attemptCount,
                    lastError: asset.lastError,
                    metadataSnapshotID: asset.metadataSnapshotID,
                    createdAt: asset.createdAt,
                    updatedAt: asset.updatedAt
                )
            )
        }

        try context.save()
    }

    private static func groupRecord(from entity: PersistedDownloadGroupStoreRecord) -> DownloadGroupRecord? {
        guard let kind = DownloadGroupKind(rawValue: entity.kind),
              let status = DownloadStatus(rawValue: entity.status) else {
            return nil
        }

        return DownloadGroupRecord(
            id: entity.id,
            scope: DownloadScope(profileID: entity.scopeProfileID, providerFingerprint: entity.scopeProviderFingerprint),
            kind: kind,
            title: entity.title,
            parentVideoID: entity.parentVideoID,
            contentType: entity.contentType,
            coverImageURL: entity.coverImageURL,
            childAssetIDs: entity.childAssetIDs,
            status: status,
            completedAssetCount: entity.completedAssetCount,
            totalAssetCount: entity.totalAssetCount,
            bytesWritten: entity.bytesWritten,
            expectedBytes: entity.expectedBytes,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    private static func assetRecord(from entity: PersistedDownloadAssetStoreRecord) -> DownloadAssetRecord? {
        guard let remoteURL = URL(string: entity.remoteURL),
              let status = DownloadStatus(rawValue: entity.status) else {
            return nil
        }

        return DownloadAssetRecord(
            id: entity.id,
            scope: DownloadScope(profileID: entity.scopeProfileID, providerFingerprint: entity.scopeProviderFingerprint),
            videoID: entity.videoID,
            contentType: entity.contentType,
            title: entity.title,
            coverImageURL: entity.coverImageURL,
            containerExtension: entity.containerExtension,
            seriesID: entity.seriesID,
            seasonNumber: entity.seasonNumber,
            remoteURL: remoteURL,
            localURL: entity.localURL.flatMap(URL.init(string:)),
            resumeDataURL: entity.resumeDataURL.flatMap(URL.init(string:)),
            status: status,
            bytesWritten: entity.bytesWritten,
            expectedBytes: entity.expectedBytes,
            attemptCount: entity.attemptCount,
            lastError: entity.lastError,
            metadataSnapshotID: entity.metadataSnapshotID,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }
}

struct DownloadStoreView: Sendable {
    let groups: [DownloadGroupRecord]
    let assets: [DownloadAssetRecord]
}

struct DownloadRemovalPlan: Sendable {
    let removedGroup: DownloadGroupRecord?
    let orphanedAssets: [DownloadAssetRecord]
    let orphanedSnapshotIDs: Set<String>
}

actor DownloadStore {
    private let persistence: any DownloadStorePersistence
    private let now: @Sendable () -> Date

    private var groupsByID: [String: DownloadGroupRecord] = [:]
    private var assetsByID: [String: DownloadAssetRecord] = [:]
    private var didLoad = false
    private var lastPersistedProgressAt: [String: Date] = [:]

    init(
        fileURL: URL? = nil,
        modelContainer: ModelContainer? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        if let modelContainer {
            self.persistence = SwiftDataDownloadStorePersistence(modelContainer: modelContainer)
        } else {
            let defaultURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appending(path: "Downloads", directoryHint: .isDirectory)
                .appending(path: "downloads.json")
            self.persistence = FileDownloadStorePersistence(fileURL: fileURL ?? defaultURL)
        }
        self.now = now
    }

    func view(scope: DownloadScope? = nil) async -> DownloadStoreView {
        await ensureLoaded()
        return DownloadStoreView(
            groups: sortedGroups(scope: scope),
            assets: sortedAssets(scope: scope)
        )
    }

    func group(id: String) async -> DownloadGroupRecord? {
        await ensureLoaded()
        return groupsByID[id]
    }

    func asset(id: String) async -> DownloadAssetRecord? {
        await ensureLoaded()
        return assetsByID[id]
    }

    func asset(scope: DownloadScope, contentType: String, videoID: Int) async -> DownloadAssetRecord? {
        await ensureLoaded()
        let key = DownloadAssetRecord.scopedVideoKey(scope: scope, contentType: contentType, videoID: videoID)
        return assetsByID.values.first(where: { $0.scopedVideoKey == key })
    }

    func groups(scope: DownloadScope? = nil) async -> [DownloadGroupRecord] {
        await ensureLoaded()
        return sortedGroups(scope: scope)
    }

    func assets(scope: DownloadScope? = nil) async -> [DownloadAssetRecord] {
        await ensureLoaded()
        return sortedAssets(scope: scope)
    }

    func completedAsset(
        videoID: Int,
        contentType: String,
        preferredScope: DownloadScope?
    ) async -> DownloadAssetRecord? {
        await ensureLoaded()

        let matching = assetsByID.values
            .filter {
                $0.videoID == videoID &&
                $0.contentType == contentType &&
                $0.status == .completed &&
                $0.localURL != nil
            }
            .sorted { $0.updatedAt > $1.updatedAt }

        if let preferredScope {
            return matching.first(where: { $0.scope.rawKey == preferredScope.rawKey }) ?? matching.first
        }

        return matching.first
    }

    func upsert(group: DownloadGroupRecord, assets: [DownloadAssetRecord]) async {
        await ensureLoaded()
        groupsByID[group.id] = group
        for asset in assets {
            assetsByID[asset.id] = asset
        }
        recomputeAllGroups()
        await persist()
    }

    func updateAssetProgress(
        id: String,
        bytesWritten: Int64,
        expectedBytes: Int64?
    ) async {
        await ensureLoaded()
        guard var asset = assetsByID[id] else { return }
        asset.bytesWritten = max(bytesWritten, 0)
        asset.expectedBytes = expectedBytes
        asset.updatedAt = now()
        if asset.status != .downloading {
            asset.status = .downloading
        }
        assetsByID[id] = asset
        recomputeAllGroups()

        let currentDate = now()
        let lastPersisted = lastPersistedProgressAt[id] ?? .distantPast
        if currentDate.timeIntervalSince(lastPersisted) >= 0.75 || asset.progressFraction >= 0.99 {
            lastPersistedProgressAt[id] = currentDate
            await persist()
        }
    }

    func updateAsset(
        id: String,
        status: DownloadStatus,
        localURL: URL? = nil,
        resumeDataURL: URL? = nil,
        bytesWritten: Int64? = nil,
        expectedBytes: Int64? = nil,
        incrementAttemptCount: Bool = false,
        lastError: String? = nil
    ) async {
        await ensureLoaded()
        guard var asset = assetsByID[id] else { return }
        asset.status = status
        if let localURL {
            asset.localURL = localURL
        }
        if let resumeDataURL {
            asset.resumeDataURL = resumeDataURL
        } else if status == .completed || status == .queued || status == .downloading || status == .preparing {
            asset.resumeDataURL = nil
        }
        if let bytesWritten {
            asset.bytesWritten = bytesWritten
        }
        if let expectedBytes {
            asset.expectedBytes = expectedBytes
        }
        if incrementAttemptCount {
            asset.attemptCount += 1
        }
        asset.lastError = lastError
        asset.updatedAt = now()
        assetsByID[id] = asset
        recomputeAllGroups()
        await persist()
    }

    func replaceAsset(_ asset: DownloadAssetRecord) async {
        await ensureLoaded()
        assetsByID[asset.id] = asset
        recomputeAllGroups()
        await persist()
    }

    func removeGroup(id: String) async -> DownloadRemovalPlan {
        await ensureLoaded()

        guard let removedGroup = groupsByID.removeValue(forKey: id) else {
            return DownloadRemovalPlan(removedGroup: nil, orphanedAssets: [], orphanedSnapshotIDs: [])
        }

        let remainingAssetIDs = Set(groupsByID.values.flatMap(\.childAssetIDs))
        var orphanedAssets: [DownloadAssetRecord] = []
        for childID in removedGroup.childAssetIDs where !remainingAssetIDs.contains(childID) {
            if let asset = assetsByID.removeValue(forKey: childID) {
                orphanedAssets.append(asset)
            }
        }

        let stillReferencedSnapshotIDs = Set(assetsByID.values.map(\.metadataSnapshotID))
        let orphanedSnapshotIDs = Set(orphanedAssets.map(\.metadataSnapshotID))
            .subtracting(stillReferencedSnapshotIDs)

        recomputeAllGroups()
        await persist()
        return DownloadRemovalPlan(
            removedGroup: removedGroup,
            orphanedAssets: orphanedAssets,
            orphanedSnapshotIDs: orphanedSnapshotIDs
        )
    }

    func removeAll(scope: DownloadScope? = nil) async -> DownloadRemovalPlan {
        await ensureLoaded()

        let targetGroups = sortedGroups(scope: scope)
        var orphanedAssets: [DownloadAssetRecord] = []
        var orphanedSnapshotIDs: Set<String> = []
        var lastRemovedGroup: DownloadGroupRecord?

        for group in targetGroups {
            let removal = await removeGroup(id: group.id)
            lastRemovedGroup = removal.removedGroup ?? lastRemovedGroup
            orphanedAssets.append(contentsOf: removal.orphanedAssets)
            orphanedSnapshotIDs.formUnion(removal.orphanedSnapshotIDs)
        }

        return DownloadRemovalPlan(
            removedGroup: lastRemovedGroup,
            orphanedAssets: orphanedAssets,
            orphanedSnapshotIDs: orphanedSnapshotIDs
        )
    }

    func restorePendingAfterLaunch() async {
        await ensureLoaded()

        let timestamp = now()
        var changed = false
        for (id, asset) in assetsByID {
            guard asset.status == .downloading || asset.status == .preparing else { continue }
            var updated = asset
            updated.status = .queued
            updated.lastError = nil
            updated.updatedAt = timestamp
            assetsByID[id] = updated
            changed = true
        }

        if changed {
            recomputeAllGroups()
            await persist()
        }
    }

    private func sortedGroups(scope: DownloadScope?) -> [DownloadGroupRecord] {
        groupsByID.values
            .filter { scope == nil || $0.scope.rawKey == scope?.rawKey }
            .sorted {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private func sortedAssets(scope: DownloadScope?) -> [DownloadAssetRecord] {
        assetsByID.values
            .filter { scope == nil || $0.scope.rawKey == scope?.rawKey }
            .sorted {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true

        do {
            guard let snapshot = try await persistence.load() else {
                groupsByID = [:]
                assetsByID = [:]
                return
            }
            groupsByID = Dictionary(uniqueKeysWithValues: snapshot.groups.map { ($0.id, $0) })
            assetsByID = Dictionary(uniqueKeysWithValues: snapshot.assets.map { ($0.id, $0) })
            recomputeAllGroups()
        } catch {
            groupsByID = [:]
            assetsByID = [:]
            logger.error("Downloads manifest load failed, resetting state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recomputeAllGroups() {
        let timestamp = now()
        for (id, group) in groupsByID {
            let children = group.childAssetIDs.compactMap { assetsByID[$0] }
            var updated = group
            updated.totalAssetCount = children.count
            updated.completedAssetCount = children.filter { $0.status == .completed }.count
            updated.bytesWritten = children.reduce(0) { $0 + max($1.bytesWritten, 0) }

            let expectedValues = children.compactMap(\.expectedBytes)
            updated.expectedBytes = expectedValues.count == children.count ? expectedValues.reduce(0, +) : nil
            updated.status = aggregateStatus(for: children)
            updated.updatedAt = max(group.updatedAt, children.map(\.updatedAt).max() ?? timestamp)
            groupsByID[id] = updated
        }
    }

    private func aggregateStatus(for assets: [DownloadAssetRecord]) -> DownloadStatus {
        guard !assets.isEmpty else { return .queued }
        if assets.allSatisfy({ $0.status == .completed }) {
            return .completed
        }
        if assets.contains(where: { $0.status == .removing }) {
            return .removing
        }
        if assets.contains(where: { $0.status == .downloading }) {
            return .downloading
        }
        if assets.contains(where: { $0.status == .preparing }) {
            return .preparing
        }
        if assets.contains(where: { $0.status == .paused }) {
            return .paused
        }
        if assets.contains(where: { $0.status == .failedTerminal }) {
            return .failedTerminal
        }
        if assets.contains(where: { $0.status == .failedRestartable }) {
            return .failedRestartable
        }
        return .queued
    }

    private func persist() async {
        do {
            let snapshot = DownloadStoreSnapshot(
                groups: groupsByID.values.sorted { $0.updatedAt > $1.updatedAt },
                assets: assetsByID.values.sorted { $0.updatedAt > $1.updatedAt }
            )
            try await persistence.save(snapshot)
        } catch {
            logger.error("Downloads manifest persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
