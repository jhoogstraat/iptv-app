//
//  SearchOrchestratorTests.swift
//  iptvTests
//
//  Created by Codex on 05.03.26.
//

import Foundation
import Testing
@testable import iptv

@MainActor
struct SearchOrchestratorTests {
    @Test
    func ensureCoverageHonorsMaxConcurrentFetches() async {
        let orchestrator = SearchOrchestrator()
        let probe = ConcurrencyProbe()
        let targets = [
            SearchCoverageTarget(contentType: .vod, category: Category(id: "1", name: "Action")),
            SearchCoverageTarget(contentType: .vod, category: Category(id: "2", name: "Drama")),
            SearchCoverageTarget(contentType: .vod, category: Category(id: "3", name: "Comedy"))
        ]

        let stream = orchestrator.ensureCoverage(
            scope: .movies,
            providerFingerprint: "provider",
            targets: targets,
            maxConcurrent: 2,
            progressProvider: {
                SearchIndexProgress(indexedCategories: 0, totalCategories: targets.count, scope: .movies)
            },
            fetch: { _ in
                await probe.begin()
                try? await Task.sleep(for: .milliseconds(100))
                await probe.end()
            }
        )

        for await _ in stream {}

        #expect(await probe.maxConcurrency() == 2)
    }
}

private actor ConcurrencyProbe {
    private var activeCount = 0
    private var maxObservedCount = 0

    func begin() {
        activeCount += 1
        maxObservedCount = max(maxObservedCount, activeCount)
    }

    func end() {
        activeCount = max(0, activeCount - 1)
    }

    func maxConcurrency() -> Int {
        maxObservedCount
    }
}
