//
//  SearchOrchestrator.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import Foundation

struct SearchCoverageTarget: Hashable {
    let contentType: XtreamContentType
    let category: Category

    var key: String {
        "\(contentType.rawValue):\(category.id)"
    }
}

@MainActor
final class SearchOrchestrator {
    private struct ScopeKey: Hashable {
        let providerFingerprint: String
        let scope: SearchMediaScope
    }

    private var inFlightCategoryKeysByScope: [ScopeKey: Set<String>] = [:]

    func ensureCoverage(
        scope: SearchMediaScope,
        providerFingerprint: String,
        targets: [SearchCoverageTarget],
        maxConcurrent: Int = 2,
        progressProvider: @escaping () async -> SearchIndexProgress,
        fetch: @escaping @MainActor (SearchCoverageTarget) async -> Void
    ) -> AsyncStream<SearchIndexProgress> {
        let scopeKey = ScopeKey(providerFingerprint: providerFingerprint, scope: scope)

        return AsyncStream { continuation in
            let producerTask = Task { @MainActor in
                continuation.yield(await progressProvider())

                var inFlight = inFlightCategoryKeysByScope[scopeKey] ?? []
                let pendingTargets = targets.filter { !inFlight.contains($0.key) }
                guard !pendingTargets.isEmpty else {
                    continuation.finish()
                    return
                }

                for target in pendingTargets {
                    inFlight.insert(target.key)
                }
                inFlightCategoryKeysByScope[scopeKey] = inFlight
                let pendingKeys = Set(pendingTargets.map(\.key))

                defer {
                    var remaining = inFlightCategoryKeysByScope[scopeKey] ?? []
                    remaining.subtract(pendingKeys)
                    if remaining.isEmpty {
                        inFlightCategoryKeysByScope[scopeKey] = nil
                    } else {
                        inFlightCategoryKeysByScope[scopeKey] = remaining
                    }
                    continuation.finish()
                }

                let concurrencyLimit = max(1, maxConcurrent)
                var iterator = pendingTargets.makeIterator()

                await withTaskGroup(of: String?.self) { group in
                    for _ in 0..<min(concurrencyLimit, pendingTargets.count) {
                        guard let target = iterator.next() else { break }
                        let targetKey = target.key
                        group.addTask {
                            guard !Task.isCancelled else { return nil }
                            await fetch(target)
                            return targetKey
                        }
                    }

                    while let completedKey = await group.next() {
                        guard let completedKey else { continue }
                        inFlightCategoryKeysByScope[scopeKey]?.remove(completedKey)
                        continuation.yield(await progressProvider())

                        if Task.isCancelled {
                            group.cancelAll()
                            continue
                        }

                        if let nextTarget = iterator.next() {
                            let nextTargetKey = nextTarget.key
                            group.addTask {
                                guard !Task.isCancelled else { return nil }
                                await fetch(nextTarget)
                                return nextTargetKey
                            }
                        }
                    }
                }
            }

            continuation.onTermination = { _ in
                producerTask.cancel()
            }
        }
    }

    func cancelAll(providerFingerprint: String) {
        inFlightCategoryKeysByScope = inFlightCategoryKeysByScope.filter { $0.key.providerFingerprint != providerFingerprint }
    }

    func cancelAll() {
        inFlightCategoryKeysByScope.removeAll()
    }
}
