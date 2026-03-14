//
//  BackgroundCatalogueRefresher.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import Foundation

struct BackgroundCatalogueRefreshTarget: Hashable, Sendable {
    let providerFingerprint: String
    let contentType: XtreamContentType
    let categoryID: String
    let categoryName: String
    let sortIndex: Int
}

actor BackgroundCatalogueRefresher {
    private struct Observer {
        let scope: SearchMediaScope
        let continuation: AsyncStream<CatalogueSyncProgress>.Continuation
    }

    private let startupDelay: Duration
    private let interRequestDelay: Duration
    private let idleDelay: Duration

    private var loopTask: Task<Void, Never>?
    private var currentProviderFingerprint: String?
    private var observers: [UUID: Observer] = [:]

    init(
        startupDelay: Duration = .seconds(20),
        interRequestDelay: Duration = .seconds(30),
        idleDelay: Duration = .seconds(30)
    ) {
        self.startupDelay = startupDelay
        self.interRequestDelay = interRequestDelay
        self.idleDelay = idleDelay
    }

    func start(
        providerFingerprint: String,
        ensureBootstrap: @escaping @Sendable () async throws -> Void,
        nextTarget: @escaping @Sendable () async throws -> BackgroundCatalogueRefreshTarget?,
        refresh: @escaping @Sendable (BackgroundCatalogueRefreshTarget) async throws -> Void,
        progress: @escaping @Sendable (SearchMediaScope, String) async -> CatalogueSyncProgress
    ) {
        guard currentProviderFingerprint != providerFingerprint || loopTask == nil else { return }

        stop()
        currentProviderFingerprint = providerFingerprint

        loopTask = Task(priority: .utility) {
            try? await Task.sleep(for: startupDelay)

            while !Task.isCancelled {
                do {
                    try await ensureBootstrap()
                    await emitProgress(providerFingerprint: providerFingerprint, provider: progress)

                    guard let target = try await nextTarget() else {
                        try await Task.sleep(for: idleDelay)
                        continue
                    }

                    try Task.checkCancellation()
                    try await refresh(target)
                    await emitProgress(providerFingerprint: providerFingerprint, provider: progress)
                    try await Task.sleep(for: interRequestDelay)
                } catch is CancellationError {
                    return
                } catch {
                    await emitProgress(providerFingerprint: providerFingerprint, provider: progress)
                    try? await Task.sleep(for: idleDelay)
                }
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        currentProviderFingerprint = nil
    }

    func observeProgress(
        scope: SearchMediaScope,
        providerFingerprint: String,
        progress: @escaping @Sendable (SearchMediaScope, String) async -> CatalogueSyncProgress
    ) -> AsyncStream<CatalogueSyncProgress> {
        AsyncStream { continuation in
            let id = UUID()
            observers[id] = Observer(scope: scope, continuation: continuation)

            let initialTask = Task {
                let value = await progress(scope, providerFingerprint)
                continuation.yield(value)
            }

            continuation.onTermination = { _ in
                initialTask.cancel()
                Task { await self.removeObserver(id: id) }
            }
        }
    }

    private func removeObserver(id: UUID) {
        observers[id] = nil
    }

    private func emitProgress(
        providerFingerprint: String,
        provider: @escaping @Sendable (SearchMediaScope, String) async -> CatalogueSyncProgress
    ) async {
        for observer in observers.values {
            let value = await provider(observer.scope, providerFingerprint)
            observer.continuation.yield(value)
        }
    }
}
