//
//  BackgroundActivityCenter.swift
//  iptv
//
//  Created by Codex on 10.03.26.
//

import Foundation
import Observation

enum BackgroundActivityState: String, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

struct BackgroundActivity: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var detail: String?
    var source: String
    var startedAt: Date
    var updatedAt: Date
    var state: BackgroundActivityState
    var currentStep: Int?
    var totalSteps: Int?
    var isPausable: Bool
    var errorDescription: String?

    var progressLabel: String? {
        guard let currentStep, let totalSteps, totalSteps > 0 else { return nil }
        return "\(min(currentStep, totalSteps))/\(totalSteps)"
    }
}

@MainActor
@Observable
final class BackgroundActivityCenter {
    private static let waitPollInterval = Duration.seconds(3)

    private(set) var activeActivities: [String: BackgroundActivity] = [:]
    private(set) var recentActivities: [BackgroundActivity] = []
    var isPaused = false

    private let maxRecentActivities = 12
    private let now: @Sendable () -> Date
    private let connectionMonitor: InternetConnectionMonitor

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        connectionMonitor: InternetConnectionMonitor = .shared
    ) {
        self.now = now
        self.connectionMonitor = connectionMonitor
    }

    var activeList: [BackgroundActivity] {
        activeActivities.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var recentList: [BackgroundActivity] {
        recentActivities
    }

    var activeCount: Int {
        activeActivities.count
    }

    var hasFailures: Bool {
        recentActivities.contains(where: { $0.state == .failed })
    }

    var recentFailureCount: Int {
        recentActivities.filter { $0.state == .failed }.count
    }

    var shouldShowIndicator: Bool {
        activeCount > 0 || hasFailures
    }

    var isWaitingForInternet: Bool {
        activeCount > 0 && !connectionMonitor.isConnected
    }

    var summaryText: String {
        if isWaitingForInternet {
            return "Waiting for internet"
        }
        if isPaused, activeCount > 0 {
            return "\(activeCount) paused"
        }
        if activeCount == 1, let activity = activeList.first {
            if let detail = activity.detail, !detail.isEmpty {
                return detail
            }
            return activity.title
        }
        if activeCount > 1 {
            return "\(activeCount) tasks in progress"
        }
        if hasFailures {
            return recentFailureCount == 1 ? "1 recent issue" : "\(recentFailureCount) recent issues"
        }
        return "Background tasks"
    }

    func start(
        id: String,
        title: String,
        detail: String? = nil,
        source: String,
        progress: (current: Int, total: Int)? = nil,
        isPausable: Bool = true
    ) {
        let timestamp = now()
        activeActivities[id] = BackgroundActivity(
            id: id,
            title: title,
            detail: detail,
            source: source,
            startedAt: activeActivities[id]?.startedAt ?? timestamp,
            updatedAt: timestamp,
            state: .running,
            currentStep: progress?.current,
            totalSteps: progress?.total,
            isPausable: isPausable,
            errorDescription: nil
        )
    }

    func update(
        id: String,
        detail: String? = nil,
        progress: (current: Int, total: Int)? = nil
    ) {
        guard var activity = activeActivities[id] else { return }
        activity.updatedAt = now()
        if let detail {
            activity.detail = detail
        }
        if let progress {
            activity.currentStep = progress.current
            activity.totalSteps = progress.total
        }
        activeActivities[id] = activity
    }

    func finish(id: String, detail: String? = nil) {
        transition(id: id, to: .completed, detail: detail, errorDescription: nil)
    }

    func fail(id: String, error: Error, detail: String? = nil) {
        transition(
            id: id,
            to: .failed,
            detail: detail ?? error.localizedDescription,
            errorDescription: error.localizedDescription
        )
    }

    func cancel(id: String, detail: String? = nil) {
        transition(id: id, to: .cancelled, detail: detail, errorDescription: nil)
    }

    func clearRecentFailures() {
        recentActivities.removeAll { $0.state == .failed }
    }

    func waitIfResumed() async throws {
        while isPaused || !connectionMonitor.isConnected {
            try Task.checkCancellation()
            try await Task.sleep(for: Self.waitPollInterval)
        }
    }

    private func transition(
        id: String,
        to state: BackgroundActivityState,
        detail: String?,
        errorDescription: String?
    ) {
        guard var activity = activeActivities.removeValue(forKey: id) else { return }
        activity.state = state
        activity.updatedAt = now()
        if let detail {
            activity.detail = detail
        }
        activity.errorDescription = errorDescription

        recentActivities.removeAll { $0.id == id }
        recentActivities.insert(activity, at: 0)
        if recentActivities.count > maxRecentActivities {
            recentActivities.removeLast(recentActivities.count - maxRecentActivities)
        }
    }
}
