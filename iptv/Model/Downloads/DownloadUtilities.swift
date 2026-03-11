//
//  DownloadUtilities.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import CryptoKit
import Foundation
import UniformTypeIdentifiers

extension String {
    nonisolated var sha256Hex: String {
        let digest = SHA256.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum DownloadIdentifiers {
    nonisolated static func assetID(scope: DownloadScope, contentType: String, videoID: Int) -> String {
        "asset-\(DownloadScope.storageKey(for: scope))-\(contentType)-\(videoID)"
    }

    nonisolated static func groupID(
        scope: DownloadScope,
        kind: DownloadGroupKind,
        parentVideoID: Int,
        seasonNumber: Int? = nil,
        episodeID: Int? = nil
    ) -> String {
        let suffix = [
            kind.rawValue,
            String(parentVideoID),
            seasonNumber.map(String.init),
            episodeID.map(String.init)
        ]
        .compactMap { $0 }
        .joined(separator: "-")

        return "group-\(DownloadScope.storageKey(for: scope))-\(suffix)"
    }

    nonisolated static func metadataSnapshotID(scope: DownloadScope, contentType: String, videoID: Int) -> String {
        "snapshot-\(DownloadScope.storageKey(for: scope))-\(contentType)-\(videoID)"
    }
}

enum DownloadFileNaming {
    nonisolated static func fileExtension(for url: URL, mimeType: String? = nil, fallback: String = "bin") -> String {
        let pathExtension = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pathExtension.isEmpty {
            return pathExtension.lowercased()
        }

        if let mimeType,
           let type = UTType(mimeType: mimeType),
           let preferred = type.preferredFilenameExtension {
            return preferred
        }

        return fallback
    }

    nonisolated static func sanitizedFileName(_ rawValue: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        let normalized = rawValue
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))

        return normalized.isEmpty ? fallback : normalized
    }
}
