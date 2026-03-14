//
//  WatchActivityStore.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation
import OSLog

nonisolated protocol WatchActivityStoring: Sendable {
    func loadAll() async -> [WatchActivityRecord]
    func recordProgress(input: WatchActivityInput, providerFingerprint: String, currentTime: Double, duration: Double?) async
    func markCompleted(input: WatchActivityInput, providerFingerprint: String) async
    func clear(for providerFingerprint: String) async
}

actor DiskWatchActivityStore: WatchActivityStoring {
    static let shared = DiskWatchActivityStore()

    private let fileURL: URL
    private let now: @Sendable () -> Date

    private var recordsByKey: [String: WatchActivityRecord] = [:]
    private var didLoad = false

    init(
        fileURL: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let defaultURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(path: "WatchActivity", directoryHint: .isDirectory)
            .appending(path: "watch_activity.json")

        self.fileURL = fileURL ?? defaultURL
        self.now = now
    }

    func loadAll() async -> [WatchActivityRecord] {
        await ensureLoaded()
        return recordsByKey.values.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    func recordProgress(
        input: WatchActivityInput,
        providerFingerprint: String,
        currentTime: Double,
        duration: Double?
    ) async {
        await ensureLoaded()

        let key = WatchActivityRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: input.contentType,
            videoID: input.videoID
        )

        let baseRecord = recordsByKey[key] ?? WatchActivityRecord.from(
            input: input,
            providerFingerprint: providerFingerprint,
            now: now()
        )

        let updated = baseRecord.updatingProgress(currentTime: currentTime, duration: duration, now: now())
        recordsByKey[key] = updated
        await persist()
    }

    func markCompleted(input: WatchActivityInput, providerFingerprint: String) async {
        await ensureLoaded()

        let key = WatchActivityRecord.makeKey(
            providerFingerprint: providerFingerprint,
            contentType: input.contentType,
            videoID: input.videoID
        )

        let baseRecord = recordsByKey[key] ?? WatchActivityRecord.from(
            input: input,
            providerFingerprint: providerFingerprint,
            now: now()
        )

        recordsByKey[key] = baseRecord.markingCompleted(now: now())
        await persist()
    }

    func clear(for providerFingerprint: String) async {
        await ensureLoaded()
        recordsByKey = recordsByKey.filter { $0.value.providerFingerprint != providerFingerprint }
        await persist()
    }

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directoryURL.path()) {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }

            guard FileManager.default.fileExists(atPath: fileURL.path()) else {
                recordsByKey = [:]
                return
            }

            let data = try Data(contentsOf: fileURL)
            let records = try JSONDecoder().decode([WatchActivityRecord].self, from: data)
            recordsByKey = Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0) })
        } catch {
            recordsByKey = [:]
            logger.error("Watch activity load failed, resetting file: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persist() async {
        do {
            let records = recordsByKey.values.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            logger.error("Watch activity persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
