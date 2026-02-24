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
            Task { @MainActor in
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

                defer {
                    continuation.finish()
                }

                _ = maxConcurrent
                for target in pendingTargets {
                    await fetch(target)
                    inFlightCategoryKeysByScope[scopeKey]?.remove(target.key)
                    continuation.yield(await progressProvider())
                }
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
