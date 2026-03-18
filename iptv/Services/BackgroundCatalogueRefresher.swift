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

    private let startupDelay: Duration
    private let interRequestDelay: Duration
    private let idleDelay: Duration

    private var loopTask: Task<Void, Never>?
    private var currentProviderFingerprint: String?
//    private var observers: [UUID: Observer] = [:]

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
        refresh: @escaping @Sendable (BackgroundCatalogueRefreshTarget) async throws -> Void
    ) {
        stop()
        currentProviderFingerprint = providerFingerprint

        loopTask = Task(priority: .utility) {
            try? await Task.sleep(for: startupDelay)

            while !Task.isCancelled {
                do {
                    try await ensureBootstrap()
//                    await emitProgress(providerFingerprint: providerFingerprint)

                    guard let target = try await nextTarget() else {
                        try await Task.sleep(for: idleDelay)
                        continue
                    }

                    try Task.checkCancellation()
                    try await refresh(target)
                    
//                    await emitProgress(providerFingerprint: providerFingerprint)
                    try await Task.sleep(for: interRequestDelay)
                } catch is CancellationError {
                    return
                } catch {
//                    await emitProgress(providerFingerprint: providerFingerprint)
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

//    private func emitProgress(
//        providerFingerprint: String,
//        provider: @escaping @Sendable (String) async ->
//    ) async {
//        for observer in observers.values {
//            let value = await provider(observer.scope, providerFingerprint)
//            observer.continuation.yield(value)
//        }
//    }
}
