//
//  OfflineAssetStore.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation

actor OfflineAssetStore {
    private let rootDirectoryURL: URL
    private let fileManager = FileManager.default

    init(rootDirectoryURL: URL? = nil) {
        let defaultDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(path: "DownloadsAssets", directoryHint: .isDirectory)
        self.rootDirectoryURL = rootDirectoryURL ?? defaultDirectory
    }

    func persistResumeData(_ data: Data, for asset: DownloadAssetRecord) throws -> URL {
        let assetDirectory = try ensureAssetDirectory(for: asset)
        let url = assetDirectory.appending(path: "resume.data")
        try data.write(to: url, options: [.atomic])
        return url
    }

    func loadResumeData(at url: URL?) throws -> Data? {
        guard let url, fileManager.fileExists(atPath: url.path()) else { return nil }
        return try Data(contentsOf: url)
    }

    func moveDownloadedFile(from temporaryURL: URL, for asset: DownloadAssetRecord) throws -> URL {
        let assetDirectory = try ensureAssetDirectory(for: asset)
        let fileName = DownloadFileNaming.sanitizedFileName(asset.title, fallback: "\(asset.videoID)")
        let ext = DownloadFileNaming.fileExtension(for: asset.remoteURL, fallback: asset.containerExtension)
        let destinationURL = assetDirectory.appending(path: "media/\(fileName).\(ext)")

        let mediaDirectory = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: mediaDirectory.path()) {
            try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: destinationURL.path()) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    func removeFiles(for asset: DownloadAssetRecord) throws {
        let assetDirectory = directoryURL(for: asset.scope, assetID: asset.id)
        if fileManager.fileExists(atPath: assetDirectory.path()) {
            try fileManager.removeItem(at: assetDirectory)
        } else {
            if let localURL = asset.localURL, fileManager.fileExists(atPath: localURL.path()) {
                try? fileManager.removeItem(at: localURL)
            }
            if let resumeDataURL = asset.resumeDataURL, fileManager.fileExists(atPath: resumeDataURL.path()) {
                try? fileManager.removeItem(at: resumeDataURL)
            }
        }
    }

    func removeFile(at url: URL?) {
        guard let url, fileManager.fileExists(atPath: url.path()) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func ensureAssetDirectory(for asset: DownloadAssetRecord) throws -> URL {
        let assetDirectory = directoryURL(for: asset.scope, assetID: asset.id)
        if !fileManager.fileExists(atPath: assetDirectory.path()) {
            try fileManager.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
        }
        return assetDirectory
    }

    private func directoryURL(for scope: DownloadScope, assetID: String) -> URL {
        rootDirectoryURL
            .appending(path: DownloadScope.storageKey(for: scope), directoryHint: .isDirectory)
            .appending(path: assetID, directoryHint: .isDirectory)
    }
}

