//
//  InternetConnectionMonitor.swift
//  iptv
//
//  Created by Codex on 13.03.26.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class InternetConnectionMonitor {
    static let shared = InternetConnectionMonitor()
    private static let reconnectPollInterval = Duration.seconds(3)

    private(set) var isConnected = true

    @ObservationIgnored private let monitor: NWPathMonitor
    @ObservationIgnored private let queue = DispatchQueue(label: "com.jhoogstraat.iptv.connection-monitor")

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        self.isConnected = monitor.currentPath.status == .satisfied

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    func waitUntilConnected() async throws {
        while !isConnected {
            try Task.checkCancellation()
            try await Task.sleep(for: Self.reconnectPollInterval)
        }
    }
}
