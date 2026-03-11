//
//  OfflineMetadataStore.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation

actor OfflineMetadataStore {
    private let rootDirectoryURL: URL
    private let fileManager = FileManager.default
    private let session: URLSession

    init(
        rootDirectoryURL: URL? = nil,
        session: URLSession = .shared
    ) {
        let defaultDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(path: "DownloadsMetadata", directoryHint: .isDirectory)
        self.rootDirectoryURL = rootDirectoryURL ?? defaultDirectory
        self.session = session
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

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotFileURL(for: prepared.snapshotID), options: [.atomic])
        return snapshot
    }

    func snapshot(id: String) async -> OfflineMetadataSnapshot? {
        try? loadSnapshot(id: id)
    }

    func removeSnapshot(id: String) async {
        let directory = snapshotDirectoryURL(for: id)
        if fileManager.fileExists(atPath: directory.path()) {
            try? fileManager.removeItem(at: directory)
        }
    }

    private func loadSnapshot(id: String) throws -> OfflineMetadataSnapshot? {
        let fileURL = snapshotFileURL(for: id)
        guard fileManager.fileExists(atPath: fileURL.path()) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(OfflineMetadataSnapshot.self, from: data)
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

    private func snapshotFileURL(for id: String) -> URL {
        snapshotDirectoryURL(for: id).appending(path: "metadata.json")
    }
}

