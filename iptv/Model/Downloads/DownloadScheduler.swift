//
//  DownloadScheduler.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation

actor DownloadScheduler {
    private let store: DownloadStore
    private let assetStore: OfflineAssetStore
    private let sessionClient: DownloadSessionClient
    private let maxConcurrentDownloads: Int
    private let onRecordsChanged: @Sendable () async -> Void

    private var eventPumpTask: Task<Void, Never>?
    private var taskIdentifierByAssetID: [String: Int] = [:]
    private var assetIDByTaskIdentifier: [Int: String] = [:]
    private var pauseRequestedAssetIDs: Set<String> = []
    private var cancelledAssetIDs: Set<String> = []
    private var delayedRetryTasks: [String: Task<Void, Never>] = [:]

    init(
        store: DownloadStore,
        assetStore: OfflineAssetStore,
        sessionClient: DownloadSessionClient,
        maxConcurrentDownloads: Int = 3,
        onRecordsChanged: @escaping @Sendable () async -> Void
    ) {
        self.store = store
        self.assetStore = assetStore
        self.sessionClient = sessionClient
        self.maxConcurrentDownloads = max(1, maxConcurrentDownloads)
        self.onRecordsChanged = onRecordsChanged
    }

    func start() async {
        guard eventPumpTask == nil else { return }

        let events = sessionClient.events
        eventPumpTask = Task {
            for await event in events {
                await self.handle(event)
            }
        }

        await store.restorePendingAfterLaunch()
        await onRecordsChanged()
        await wake()
    }

    func wake() async {
        let view = await store.view()
        let activeCount = taskIdentifierByAssetID.count
        let availableSlots = max(0, maxConcurrentDownloads - activeCount)
        guard availableSlots > 0 else { return }

        let candidates = view.assets
            .filter { $0.status == .queued }
            .prefix(availableSlots)

        for asset in candidates {
            await startAsset(asset)
        }
    }

    func pause(ids: [String]) async {
        for id in ids {
            if let group = await store.group(id: id) {
                await pause(ids: group.childAssetIDs)
                continue
            }

            guard let asset = await store.asset(id: id) else { continue }

            if let taskIdentifier = taskIdentifierByAssetID[asset.id] {
                pauseRequestedAssetIDs.insert(asset.id)
                let resumeData = await sessionClient.pause(taskIdentifier: taskIdentifier)
                taskIdentifierByAssetID[asset.id] = nil
                assetIDByTaskIdentifier[taskIdentifier] = nil

                if let resumeData, !resumeData.isEmpty {
                    do {
                        let resumeDataURL = try await assetStore.persistResumeData(resumeData, for: asset)
                        await store.updateAsset(id: asset.id, status: .paused, resumeDataURL: resumeDataURL, lastError: nil)
                    } catch {
                        await store.updateAsset(id: asset.id, status: .paused, lastError: error.localizedDescription)
                    }
                } else {
                    await store.updateAsset(id: asset.id, status: .paused, lastError: nil)
                }
            } else if asset.status == .queued || asset.status == .failedRestartable {
                await store.updateAsset(id: asset.id, status: .paused, lastError: nil)
            }
        }

        await onRecordsChanged()
        await wake()
    }

    func resume(ids: [String]) async {
        for id in ids {
            if let group = await store.group(id: id) {
                await resume(ids: group.childAssetIDs)
                continue
            }

            guard let asset = await store.asset(id: id) else { continue }
            delayedRetryTasks[asset.id]?.cancel()
            delayedRetryTasks[asset.id] = nil
            await store.updateAsset(id: asset.id, status: .queued, lastError: nil)
        }

        await onRecordsChanged()
        await wake()
    }

    func retry(ids: [String]) async {
        for id in ids {
            if let group = await store.group(id: id) {
                await retry(ids: group.childAssetIDs)
                continue
            }

            guard let asset = await store.asset(id: id) else { continue }
            delayedRetryTasks[asset.id]?.cancel()
            delayedRetryTasks[asset.id] = nil
            if asset.resumeDataURL != nil {
                await assetStore.removeFile(at: asset.resumeDataURL)
            }
            await store.updateAsset(
                id: asset.id,
                status: .queued,
                resumeDataURL: URL(fileURLWithPath: ""),
                bytesWritten: 0,
                expectedBytes: nil,
                lastError: nil
            )
            if let refreshed = await store.asset(id: asset.id), refreshed.resumeDataURL?.path() == "" {
                var reset = refreshed
                reset.resumeDataURL = nil
                await store.replaceAsset(reset)
            }
        }

        await onRecordsChanged()
        await wake()
    }

    func cancel(ids: [String]) async {
        for id in ids {
            if let group = await store.group(id: id) {
                await cancel(ids: group.childAssetIDs)
                continue
            }
            guard let asset = await store.asset(id: id) else { continue }
            cancelledAssetIDs.insert(asset.id)
            if let taskIdentifier = taskIdentifierByAssetID[asset.id] {
                sessionClient.cancel(taskIdentifier: taskIdentifier)
                taskIdentifierByAssetID[asset.id] = nil
                assetIDByTaskIdentifier[taskIdentifier] = nil
            }
            delayedRetryTasks[asset.id]?.cancel()
            delayedRetryTasks[asset.id] = nil
        }
    }

    private func startAsset(_ asset: DownloadAssetRecord) async {
        await store.updateAsset(id: asset.id, status: .preparing, lastError: nil)

        let taskIdentifier: Int
        do {
            if let resumeData = try await assetStore.loadResumeData(at: asset.resumeDataURL), !resumeData.isEmpty {
                taskIdentifier = sessionClient.resumeDownload(with: resumeData)
            } else {
                taskIdentifier = sessionClient.startDownload(from: asset.remoteURL)
            }
        } catch {
            taskIdentifier = sessionClient.startDownload(from: asset.remoteURL)
        }

        taskIdentifierByAssetID[asset.id] = taskIdentifier
        assetIDByTaskIdentifier[taskIdentifier] = asset.id
        await store.updateAsset(id: asset.id, status: .downloading, incrementAttemptCount: true, lastError: nil)
        await onRecordsChanged()
    }

    private func handle(_ event: DownloadSessionClient.Event) async {
        switch event {
        case .progress(let taskIdentifier, _, let totalBytesWritten, let totalBytesExpected):
            guard let assetID = assetIDByTaskIdentifier[taskIdentifier] else { return }
            await store.updateAssetProgress(
                id: assetID,
                bytesWritten: totalBytesWritten,
                expectedBytes: totalBytesExpected > 0 ? totalBytesExpected : nil
            )
            await onRecordsChanged()

        case .finished(let taskIdentifier, let temporaryURL):
            guard let assetID = assetIDByTaskIdentifier.removeValue(forKey: taskIdentifier) else { return }
            taskIdentifierByAssetID[assetID] = nil
            pauseRequestedAssetIDs.remove(assetID)
            cancelledAssetIDs.remove(assetID)

            guard let asset = await store.asset(id: assetID) else { return }
            do {
                let localURL = try await assetStore.moveDownloadedFile(from: temporaryURL, for: asset)
                await assetStore.removeFile(at: asset.resumeDataURL)
                await store.updateAsset(
                    id: assetID,
                    status: .completed,
                    localURL: localURL,
                    bytesWritten: asset.expectedBytes ?? asset.bytesWritten,
                    expectedBytes: asset.expectedBytes,
                    lastError: nil
                )
            } catch {
                await store.updateAsset(
                    id: assetID,
                    status: .failedTerminal,
                    lastError: error.localizedDescription
                )
            }

            await onRecordsChanged()
            await wake()

        case .failed(let taskIdentifier, let errorDomain, let errorCode, let description, let resumeData):
            guard let assetID = assetIDByTaskIdentifier.removeValue(forKey: taskIdentifier) else { return }
            taskIdentifierByAssetID[assetID] = nil

            let wasPauseRequest = pauseRequestedAssetIDs.remove(assetID) != nil
            let wasCancelled = cancelledAssetIDs.remove(assetID) != nil

            guard let asset = await store.asset(id: assetID) else { return }

            if wasCancelled {
                await store.updateAsset(id: assetID, status: .queued, lastError: nil)
                await onRecordsChanged()
                await wake()
                return
            }

            if wasPauseRequest {
                if let resumeData, !resumeData.isEmpty {
                    do {
                        let resumeDataURL = try await assetStore.persistResumeData(resumeData, for: asset)
                        await store.updateAsset(id: assetID, status: .paused, resumeDataURL: resumeDataURL, lastError: nil)
                    } catch {
                        await store.updateAsset(id: assetID, status: .paused, lastError: error.localizedDescription)
                    }
                } else {
                    await store.updateAsset(id: assetID, status: .paused, lastError: nil)
                }
                await onRecordsChanged()
                await wake()
                return
            }

            let finalDescription = description
            if let resumeData, !resumeData.isEmpty {
                do {
                    let resumeDataURL = try await assetStore.persistResumeData(resumeData, for: asset)
                    await store.updateAsset(id: assetID, status: .failedRestartable, resumeDataURL: resumeDataURL, lastError: finalDescription)
                } catch {
                    await store.updateAsset(id: assetID, status: .failedRestartable, lastError: finalDescription)
                }
            } else {
                await store.updateAsset(id: assetID, status: .failedRestartable, lastError: finalDescription)
            }

            if shouldAutoRetry(errorDomain: errorDomain, errorCode: errorCode, attemptCount: asset.attemptCount) {
                scheduleAutoRetry(assetID: assetID)
            }

            await onRecordsChanged()
            await wake()
        }
    }

    private func scheduleAutoRetry(assetID: String) {
        delayedRetryTasks[assetID]?.cancel()
        delayedRetryTasks[assetID] = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await self.store.updateAsset(id: assetID, status: .queued, lastError: nil)
            await self.onRecordsChanged()
            await self.wake()
            self.delayedRetryTasks[assetID] = nil
        }
    }

    private func shouldAutoRetry(errorDomain: String, errorCode: Int, attemptCount: Int) -> Bool {
        guard attemptCount < 1 else { return false }
        guard errorDomain == NSURLErrorDomain else { return false }
        let code = URLError.Code(rawValue: errorCode)
        switch code {
        case .timedOut, .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
