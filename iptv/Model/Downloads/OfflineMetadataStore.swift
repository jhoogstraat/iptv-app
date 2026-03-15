//
//  OfflineMetadataStore.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation
import OSLog
import SwiftData

@ModelActor
private actor DatabaseOfflineMetadataStorePersistence {

    func loadSnapshot(id: String) throws -> OfflineMetadataSnapshot? {
        guard let record = try fetchRecord(id: id) else { return nil }
        return try Self.snapshot(from: record)
    }

    func save(_ snapshot: OfflineMetadataSnapshot) throws {
        modelContext.insert(try Self.record(from: snapshot))
        try modelContext.save()
    }

    func removeSnapshot(id: String) throws {
        try modelContext.delete(
            model: PersistedOfflineMetadataStoreRecord.self,
            where: #Predicate { $0.id == id }
        )
        try modelContext.save()
    }

    private func fetchRecord(id: String) throws -> PersistedOfflineMetadataStoreRecord? {
        let descriptor = FetchDescriptor<PersistedOfflineMetadataStoreRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
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
    nonisolated private static let log = Logger(subsystem: "iptv", category: "OfflineMetadataStore")
    private let rootDirectoryURL: URL
    private let fileManager = FileManager.default
    private let session: URLSession
    private let persistence: DatabaseOfflineMetadataStorePersistence

    init(
        modelContainer: ModelContainer,
        rootDirectoryURL: URL? = nil,
        session: URLSession = .shared
    ) {
        let defaultDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(path: "DownloadsMetadata", directoryHint: .isDirectory)
        self.rootDirectoryURL = rootDirectoryURL ?? defaultDirectory
        self.session = session
        self.persistence = DatabaseOfflineMetadataStorePersistence(modelContainer: modelContainer)
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
        do {
            return try await persistence.loadSnapshot(id: id)
        } catch {
            Self.log.error("Failed to load offline metadata snapshot: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func removeSnapshot(id: String) async {
        do {
            try await persistence.removeSnapshot(id: id)
        } catch {
            Self.log.error("Failed to remove offline metadata snapshot: \(error.localizedDescription, privacy: .public)")
        }

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
