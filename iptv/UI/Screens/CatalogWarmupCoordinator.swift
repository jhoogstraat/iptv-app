//
//  CatalogWarmupCoordinator.swift
//  iptv
//
//  Created by Codex on 10.03.26.
//

import Foundation
import OSLog

@MainActor
final class CatalogWarmupCoordinator {
    private var task: Task<Void, Never>?
    private var lastIndexKey: String?

    func start(providerRevision: Int, catalog: Catalog) {
        let indexKey = "\(providerRevision)"
        guard indexKey != lastIndexKey else { return }

        lastIndexKey = indexKey
        task?.cancel()

        task = Task(priority: .utility) { @MainActor in
            await self.run(catalog: catalog)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func run(catalog: Catalog) async {
        guard catalog.hasProviderConfiguration else { return }

        do {
            try await catalog.runBackgroundCatalogueIndex()
        } catch is CancellationError {
            return
        } catch {
            logger.debug("Catalog indexing failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
