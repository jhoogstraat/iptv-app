import Foundation
import SQLiteData

enum DownloadStatus: Int, QueryBindable, Sendable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

@Table("download_items")
nonisolated struct DownloadItem: Hashable, Identifiable, Sendable {
    let id: Int
    let profileID: UserProfile.ID
    let providerID: Provider.ID
    let mediaType: MediaType
    let sourceID: Int
    var title: String
    var artworkURL: URL?
    let remoteURL: URL
    var localPath: String?
    var status: DownloadStatus = .queued
    var errorMessage: String?
    var createdAt: Date = .now
    var updatedAt: Date = .now
}

enum DownloadStore {
    static func item(
        for media: Media,
        providerID: Provider.ID,
        database: any DatabaseWriter
    ) -> DownloadItem? {
        let profileID = UserProfileStore.activeProfileID()
        return try? database.read { db in
            try DownloadItem.where {
                $0.profileID.eq(profileID)
                    .and($0.providerID.eq(providerID))
                    .and($0.mediaType.eq(media.type))
                    .and($0.sourceID.eq(media.sourceID))
            }.fetchOne(db)
        }
    }

    static func localPlaybackURL(
        for media: Media,
        providerID: Provider.ID,
        database: any DatabaseWriter
    ) -> URL? {
        guard let item = item(for: media, providerID: providerID, database: database),
              item.status == .completed,
              let path = item.localPath,
              FileManager.default.fileExists(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }
}

@MainActor
final class DownloadCoordinator {
    static let shared = DownloadCoordinator()

    private var tasks: [DownloadItem.ID: Task<Void, Never>] = [:]

    func enqueue(
        _ media: Media,
        providerID: Provider.ID,
        remoteURL: URL,
        database: any DatabaseWriter
    ) throws {
        guard media.type == .movie || media.type == .episode else {
            throw DownloadError.unsupportedContent
        }
        let profileID = UserProfileStore.activeProfileID()
        let now = Date()
        let item = try database.write { db in
            try DownloadItem.insert {
                DownloadItem.Draft(
                    id: nil,
                    profileID: profileID,
                    providerID: providerID,
                    mediaType: media.type,
                    sourceID: media.sourceID,
                    title: media.title,
                    artworkURL: media.coverURL ?? media.backdropURL,
                    remoteURL: remoteURL,
                    localPath: nil,
                    status: .queued,
                    errorMessage: nil,
                    createdAt: now,
                    updatedAt: now
                )
            } onConflict: {
                ($0.profileID, $0.providerID, $0.mediaType, $0.sourceID)
            } doUpdate: {
                $0.remoteURL = remoteURL
                $0.status = DownloadStatus.queued
                $0.errorMessage = #bind(nil)
                $0.updatedAt = now
            }.execute(db)

            return try DownloadItem.where {
                $0.profileID.eq(profileID)
                    .and($0.providerID.eq(providerID))
                    .and($0.mediaType.eq(media.type))
                    .and($0.sourceID.eq(media.sourceID))
            }.fetchOne(db)
        }
        guard let item else { throw DownloadError.persistenceFailed }
        start(item, database: database)
    }

    func pause(_ item: DownloadItem, database: any DatabaseWriter) {
        tasks[item.id]?.cancel()
        tasks[item.id] = nil
        update(item.id, status: .paused, error: nil, database: database)
    }

    func resume(_ item: DownloadItem, database: any DatabaseWriter) {
        start(item, database: database)
    }

    func remove(_ item: DownloadItem, database: any DatabaseWriter) throws {
        tasks[item.id]?.cancel()
        tasks[item.id] = nil
        if let localPath = item.localPath {
            try? FileManager.default.removeItem(atPath: localPath)
        }
        try database.write { db in
            try DownloadItem.find(item.id).delete().execute(db)
        }
    }

    private func start(_ item: DownloadItem, database: any DatabaseWriter) {
        guard tasks[item.id] == nil else { return }
        update(item.id, status: .downloading, error: nil, database: database)
        tasks[item.id] = Task { [weak self] in
            do {
                let (temporaryURL, response) = try await URLSession.shared.download(from: item.remoteURL)
                try Task.checkCancellation()
                if let response = response as? HTTPURLResponse,
                   !(200...299).contains(response.statusCode) {
                    throw DownloadError.httpStatus(response.statusCode)
                }
                let destination = try Self.destinationURL(for: item)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                self?.complete(item.id, localPath: destination.path, database: database)
            } catch is CancellationError {
                // The explicit pause/remove action owns the persisted state.
            } catch {
                self?.update(item.id, status: .failed, error: error.localizedDescription, database: database)
            }
            self?.tasks[item.id] = nil
        }
    }

    private func complete(_ id: DownloadItem.ID, localPath: String, database: any DatabaseWriter) {
        try? database.write { db in
            try DownloadItem.find(id).update {
                $0.localPath = #bind(localPath)
                $0.status = DownloadStatus.completed
                $0.errorMessage = #bind(nil)
                $0.updatedAt = Date()
            }.execute(db)
        }
    }

    private func update(
        _ id: DownloadItem.ID,
        status: DownloadStatus,
        error: String?,
        database: any DatabaseWriter
    ) {
        try? database.write { db in
            try DownloadItem.find(id).update {
                $0.status = status
                $0.errorMessage = #bind(error)
                $0.updatedAt = Date()
            }.execute(db)
        }
    }

    private static func destinationURL(for item: DownloadItem) throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root
            .appending(path: "Downloads", directoryHint: .isDirectory)
            .appending(path: String(item.profileID), directoryHint: .isDirectory)
            .appending(path: String(item.providerID), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = item.remoteURL.pathExtension
        let filename = "\(item.mediaType.rawValue)-\(item.sourceID)" + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
        return directory.appending(path: filename)
    }

    enum DownloadError: LocalizedError {
        case unsupportedContent
        case persistenceFailed
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedContent: "Only movies and episodes can be downloaded."
            case .persistenceFailed: "The download could not be saved."
            case .httpStatus(let status): "The provider returned HTTP \(status)."
            }
        }
    }
}
