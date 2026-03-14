//
//  OfflineMetadataStore.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation
import SwiftData

private protocol OfflineMetadataStorePersistence: Sendable {
    func loadSnapshot(id: String) async throws -> OfflineMetadataSnapshot?
    func save(_ snapshot: OfflineMetadataSnapshot) async throws
    func removeSnapshot(id: String) async throws
}

private actor FileOfflineMetadataStorePersistence: OfflineMetadataStorePersistence {
    private let fileManager = FileManager.default
    private let rootDirectoryURL: URL

    init(rootDirectoryURL: URL) {
        self.rootDirectoryURL = rootDirectoryURL
    }

    func loadSnapshot(id: String) async throws -> OfflineMetadataSnapshot? {
        let fileURL = snapshotFileURL(for: id)
        guard fileManager.fileExists(atPath: fileURL.path()) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(OfflineMetadataSnapshot.self, from: data)
    }

    func save(_ snapshot: OfflineMetadataSnapshot) async throws {
        let directoryURL = snapshotDirectoryURL(for: snapshot.id)
        if !fileManager.fileExists(atPath: directoryURL.path()) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotFileURL(for: snapshot.id), options: [.atomic])
    }

    func removeSnapshot(id: String) async throws {
        let directoryURL = snapshotDirectoryURL(for: id)
        guard fileManager.fileExists(atPath: directoryURL.path()) else { return }
        try fileManager.removeItem(at: directoryURL)
    }

    private func snapshotDirectoryURL(for id: String) -> URL {
        rootDirectoryURL.appending(path: id, directoryHint: .isDirectory)
    }

    private func snapshotFileURL(for id: String) -> URL {
        snapshotDirectoryURL(for: id).appending(path: "metadata.json")
    }
}

private actor SwiftDataOfflineMetadataStorePersistence: OfflineMetadataStorePersistence {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func loadSnapshot(id: String) async throws -> OfflineMetadataSnapshot? {
        let context = ModelContext(modelContainer)
        guard let record = try fetchRecord(id: id, context: context) else { return nil }
        return try Self.snapshot(from: record)
    }

    func save(_ snapshot: OfflineMetadataSnapshot) async throws {
        let context = ModelContext(modelContainer)
        if let existing = try fetchRecord(id: snapshot.id, context: context) {
            context.delete(existing)
        }
        context.insert(try Self.record(from: snapshot))
        try context.save()
    }

    func removeSnapshot(id: String) async throws {
        let context = ModelContext(modelContainer)
        guard let record = try fetchRecord(id: id, context: context) else { return }
        context.delete(record)
        try context.save()
    }

    private func fetchRecord(
        id: String,
        context: ModelContext
    ) throws -> PersistedOfflineMetadataStoreRecord? {
        let descriptor = FetchDescriptor<PersistedOfflineMetadataStoreRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private static func record(
        from snapshot: OfflineMetadataSnapshot
    ) throws -> PersistedOfflineMetadataStoreRecord {
        let artworkPayload = try JSONEncoder().encode(snapshot.artworkByRemoteURL.mapValues(\.absoluteString))
        let movieInfoPayload = try snapshot.movieInfo.map { try JSONEncoder().encode($0) }
        let seriesInfoPayload = try snapshot.seriesInfo.map { try JSONEncoder().encode($0) }

        return PersistedOfflineMetadataStoreRecord(
            id: snapshot.id,
            scopeProfileID: snapshot.scope.profileID,
            scopeProviderFingerprint: snapshot.scope.providerFingerprint,
            kind: snapshot.kind.rawValue,
            videoID: snapshot.videoID,
            contentType: snapshot.contentType,
            title: snapshot.title,
            coverImageURL: snapshot.coverImageURL,
            artworkPayload: artworkPayload,
            movieInfoPayload: movieInfoPayload,
            seriesInfoPayload: seriesInfoPayload,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
    }

    private static func snapshot(
        from record: PersistedOfflineMetadataStoreRecord
    ) throws -> OfflineMetadataSnapshot? {
        guard let kind = OfflineMetadataKind(rawValue: record.kind) else { return nil }

        let artworkStrings = try JSONDecoder().decode([String: String].self, from: record.artworkPayload)
        let artworkByRemoteURL = artworkStrings.reduce(into: [String: URL]()) { partialResult, entry in
            guard let localURL = URL(string: entry.value) else { return }
            partialResult[entry.key] = localURL
        }

        let movieInfo = try record.movieInfoPayload.map {
            try JSONDecoder().decode(CachedVideoInfoDTO.self, from: $0)
        }
        let seriesInfo = try record.seriesInfoPayload.map {
            try JSONDecoder().decode(XtreamSeries.self, from: $0)
        }

        return OfflineMetadataSnapshot(
            id: record.id,
            scope: DownloadScope(
                profileID: record.scopeProfileID,
                providerFingerprint: record.scopeProviderFingerprint
            ),
            kind: kind,
            videoID: record.videoID,
            contentType: record.contentType,
            title: record.title,
            coverImageURL: record.coverImageURL,
            artworkByRemoteURL: artworkByRemoteURL,
            movieInfo: movieInfo,
            seriesInfo: seriesInfo,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }
}

actor OfflineMetadataStore {
    private let rootDirectoryURL: URL
    private let fileManager = FileManager.default
    private let session: URLSession
    private let persistence: any OfflineMetadataStorePersistence

    init(
        rootDirectoryURL: URL? = nil,
        modelContainer: ModelContainer? = nil,
        session: URLSession = .shared
    ) {
        let defaultDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(path: "DownloadsMetadata", directoryHint: .isDirectory)
        self.rootDirectoryURL = rootDirectoryURL ?? defaultDirectory
        self.session = session
        if let modelContainer {
            self.persistence = SwiftDataOfflineMetadataStorePersistence(modelContainer: modelContainer)
        } else {
            self.persistence = FileOfflineMetadataStorePersistence(rootDirectoryURL: self.rootDirectoryURL)
        }
    }

    func store(prepared: DownloadPreparedMetadata, scope: DownloadScope) async throws -> OfflineMetadataSnapshot {
        try ensureRootDirectoryExists()

        let snapshotDirectory = snapshotDirectoryURL(for: prepared.snapshotID)
        if !fileManager.fileExists(atPath: snapshotDirectory.path()) {
            try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        }

        let artworkDirectory = snapshotDirectory.appending(path: "artwork", directoryHint: .isDirectory)
        if !fileManager.fileExists(atPath: artworkDirectory.path()) {
            try fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        }

        let artworkMap = await downloadArtwork(urls: prepared.artworkURLs, into: artworkDirectory)
        let currentDate = Date()
        let snapshot = OfflineMetadataSnapshot(
            id: prepared.snapshotID,
            scope: scope,
            kind: prepared.kind,
            videoID: prepared.videoID,
            contentType: prepared.contentType,
            title: prepared.title,
            coverImageURL: prepared.coverImageURL,
            artworkByRemoteURL: artworkMap,
            movieInfo: prepared.movieInfo,
            seriesInfo: prepared.seriesInfo,
            createdAt: currentDate,
            updatedAt: currentDate
        )

        try await persistence.save(snapshot)
        return snapshot
    }

    func snapshot(id: String) async -> OfflineMetadataSnapshot? {
        try? await persistence.loadSnapshot(id: id)
    }

    func removeSnapshot(id: String) async {
        try? await persistence.removeSnapshot(id: id)

        let directoryURL = snapshotDirectoryURL(for: id)
        if fileManager.fileExists(atPath: directoryURL.path()) {
            try? fileManager.removeItem(at: directoryURL)
        }
    }

    private func downloadArtwork(urls: [URL], into directoryURL: URL) async -> [String: URL] {
        var mapping: [String: URL] = [:]
        var seen = Set<String>()

        for url in urls where seen.insert(url.absoluteString).inserted {
            do {
                let (data, response) = try await session.data(from: url)
                guard !data.isEmpty else { continue }
                let mimeType = (response as? HTTPURLResponse)?.mimeType
                let ext = DownloadFileNaming.fileExtension(for: url, mimeType: mimeType, fallback: "img")
                let baseName = DownloadFileNaming.sanitizedFileName(url.deletingPathExtension().lastPathComponent, fallback: UUID().uuidString)
                let localURL = directoryURL.appending(path: "\(baseName).\(ext)")
                try data.write(to: localURL, options: [.atomic])
                mapping[url.absoluteString] = localURL
            } catch {
                continue
            }
        }

        return mapping
    }

    private func ensureRootDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path()) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func snapshotDirectoryURL(for id: String) -> URL {
        rootDirectoryURL.appending(path: id, directoryHint: .isDirectory)
    }
}
