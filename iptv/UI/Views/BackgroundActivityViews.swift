//
//  BackgroundActivityViews.swift
//  iptv
//
//  Created by Codex on 10.03.26.
//

import SwiftUI

private enum CatalogueArea: String, CaseIterable, Identifiable {
    case movies
    case series
    case liveTV

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movies:
            return "Movies"
        case .series:
            return "Series"
        case .liveTV:
            return "TV"
        }
    }

    var idleSubtitle: String {
        switch self {
        case .movies:
            return "Waiting to index your movie catalogue."
        case .series:
            return "Waiting to index your series catalogue and episodes."
        case .liveTV:
            return "Live TV indexing is not available in this version."
        }
    }
}

private enum CatalogueRowStatus {
    case idle
    case running
    case paused
    case waitingForInternet
    case success
    case failure

    var isActive: Bool {
        switch self {
        case .running, .paused, .waitingForInternet:
            return true
        case .idle, .success, .failure:
            return false
        }
    }
}

private struct CatalogueRowModel: Identifiable {
    let area: CatalogueArea
    let status: CatalogueRowStatus
    let subtitle: String
    let updatedAt: Date?

    var id: String { area.id }
    var title: String { area.title }
}

private struct CatalogueStatusSnapshot {
    let rows: [CatalogueRowModel]

    init(activityCenter: BackgroundActivityCenter) {
        self.rows = CatalogueArea.allCases.map { area in
            Self.makeRow(for: area, activityCenter: activityCenter)
        }
    }

    var hasActiveWork: Bool {
        rows.contains { $0.status.isActive }
    }

    var hasWaitingForInternet: Bool {
        rows.contains { $0.status == .waitingForInternet }
    }

    var hasPausedWork: Bool {
        rows.contains { $0.status == .paused }
    }

    var hasFailure: Bool {
        rows.contains { $0.status == .failure }
    }

    var shouldShowIndicator: Bool {
        hasActiveWork || hasFailure
    }

    var indicatorTitle: String {
        if hasWaitingForInternet {
            return "Waiting for internet"
        }
        if hasPausedWork {
            return "Catalogue indexing paused"
        }
        if hasFailure && !hasActiveWork {
            return "Catalogue indexing needs attention"
        }
        return "Catalogue indexing in progress"
    }

    var accessibilityValue: String {
        if let activeRow = rows.first(where: { $0.status.isActive }) {
            return "\(activeRow.title): \(activeRow.subtitle)"
        }
        if let failureRow = rows.first(where: { $0.status == .failure }) {
            return "\(failureRow.title): \(failureRow.subtitle)"
        }
        return "No catalogue indexing in progress"
    }

    private static func makeRow(
        for area: CatalogueArea,
        activityCenter: BackgroundActivityCenter
    ) -> CatalogueRowModel {
        let activeCandidates = matchingActivities(
            for: area,
            in: activityCenter.activeList
        ).sorted { lhs, rhs in
            activePriority(lhs: lhs, rhs: rhs)
        }

        if let active = activeCandidates.first {
            return CatalogueRowModel(
                area: area,
                status: activeStatus(for: active, activityCenter: activityCenter),
                subtitle: activeSubtitle(for: active, activityCenter: activityCenter),
                updatedAt: active.updatedAt
            )
        }

        let recentCandidates = matchingActivities(
            for: area,
            in: activityCenter.recentList
        ).sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        if let recent = recentCandidates.first {
            return CatalogueRowModel(
                area: area,
                status: recentStatus(for: recent),
                subtitle: terminalSubtitle(for: recent, area: area),
                updatedAt: recent.updatedAt
            )
        }

        return CatalogueRowModel(
            area: area,
            status: .idle,
            subtitle: area.idleSubtitle,
            updatedAt: nil
        )
    }

    private static func matchingActivities(
        for area: CatalogueArea,
        in activities: [BackgroundActivity]
    ) -> [BackgroundActivity] {
        activities.filter { mappedAreas(for: $0).contains(area) }
    }

    private static func mappedAreas(for activity: BackgroundActivity) -> Set<CatalogueArea> {
        let id = activity.id.lowercased()
        var result = Set<CatalogueArea>()

        if id.hasPrefix("background-index:movies") {
            result.insert(.movies)
        } else if id.hasPrefix("background-index:series") {
            result.insert(.series)
        } else if id.hasPrefix("background-index:live") {
            result.insert(.liveTV)
        }

        return result
    }

    private static func activePriority(lhs: BackgroundActivity, rhs: BackgroundActivity) -> Bool {
        let lhsHasProgress = hasNumericProgress(lhs)
        let rhsHasProgress = hasNumericProgress(rhs)
        if lhsHasProgress != rhsHasProgress {
            return lhsHasProgress
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func hasNumericProgress(_ activity: BackgroundActivity) -> Bool {
        guard let current = activity.currentStep,
              let total = activity.totalSteps else {
            return false
        }
        return total > 0 && current >= 0
    }

    private static func activeStatus(
        for activity: BackgroundActivity,
        activityCenter: BackgroundActivityCenter
    ) -> CatalogueRowStatus {
        if activityCenter.isWaitingForInternet, activity.isPausable {
            return .waitingForInternet
        }
        if activityCenter.isPaused, activity.isPausable {
            return .paused
        }
        return .running
    }

    private static func recentStatus(for activity: BackgroundActivity) -> CatalogueRowStatus {
        switch activity.state {
        case .completed:
            return .success
        case .failed:
            return .failure
        case .cancelled, .running:
            return .idle
        }
    }

    private static func activeSubtitle(
        for activity: BackgroundActivity,
        activityCenter: BackgroundActivityCenter
    ) -> String {
        if activityCenter.isWaitingForInternet {
            return "Waiting for internet"
        }
        if activityCenter.isPaused, activity.isPausable {
            return "Paused"
        }

        if let current = activity.currentStep,
           let total = activity.totalSteps,
           total > 0 {
            let progressText = "\(min(current, total)) / \(total)"
            if let category = currentCategoryName(from: activity) {
                return "\(progressText) • \(category)"
            }
            return progressText
        }

        return "Indexing your provider"
    }

    private static func terminalSubtitle(
        for activity: BackgroundActivity,
        area: CatalogueArea
    ) -> String {
        switch activity.state {
        case .completed:
            return "Up to date"
        case .failed:
            return failureSummary(for: activity)
        case .cancelled, .running:
            return area.idleSubtitle
        }
    }

    private static func failureSummary(for activity: BackgroundActivity) -> String {
        guard let errorDescription = activity.errorDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !errorDescription.isEmpty else {
            return "Needs attention"
        }

        if errorDescription.localizedCaseInsensitiveContains("internet") ||
            errorDescription.localizedCaseInsensitiveContains("network") ||
            errorDescription.localizedCaseInsensitiveContains("offline") {
            return "Couldn't reach the server"
        }

        return "Needs attention"
    }

    private static func currentCategoryName(from activity: BackgroundActivity) -> String? {
        guard let detail = activity.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty else {
            return nil
        }

        let lowercased = detail.lowercased()

        if lowercased.hasPrefix("checking ") ||
            lowercased.hasPrefix("updating ") ||
            lowercased.hasPrefix("organising ") ||
            lowercased.hasPrefix("indexing ") ||
            lowercased.hasPrefix("processing ") ||
            lowercased.hasPrefix("waiting ") ||
            lowercased == "up to date" {
            return nil
        }

        return detail
    }
}

struct BackgroundActivityIndicatorView: View {
    @Bindable var activityCenter: BackgroundActivityCenter
    @State private var isPresentingDetails = false

    private var snapshot: CatalogueStatusSnapshot {
        CatalogueStatusSnapshot(activityCenter: activityCenter)
    }

    var body: some View {
        if snapshot.shouldShowIndicator {
            Button {
                isPresentingDetails = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)

                    Circle()
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)

                    indicatorIcon
                }
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(snapshot.indicatorTitle)
            .accessibilityValue(snapshot.accessibilityValue)
            .sheet(isPresented: $isPresentingDetails) {
                NavigationStack {
                    BackgroundActivityDetailsScreen(activityCenter: activityCenter)
                }
                #if os(macOS)
                .frame(minWidth: 440, idealWidth: 480, minHeight: 320, idealHeight: 380)
                #endif
            }
        }
    }

    @ViewBuilder
    private var indicatorIcon: some View {
        if snapshot.hasWaitingForInternet {
            Image(systemName: "wifi.slash")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.orange)
        } else if snapshot.hasPausedWork {
            Image(systemName: "pause.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.orange)
        } else if snapshot.hasFailure && !snapshot.hasActiveWork {
            Image(systemName: "exclamationmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.red)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}

struct BackgroundActivityDetailsScreen: View {
    @Bindable var activityCenter: BackgroundActivityCenter
    @Environment(Catalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var isRestarting = false

    private var snapshot: CatalogueStatusSnapshot {
        CatalogueStatusSnapshot(activityCenter: activityCenter)
    }

    var body: some View {
        List {
            Section("Catalogue Status") {
                ForEach(snapshot.rows) { row in
                    catalogueRow(row)
                }
            }

            controlsSection
        }
        .navigationTitle("Catalogue Indexing")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var controlsSection: some View {
        Section("Controls") {
            Button(activityCenter.isPaused ? "Resume catalogue indexing" : "Pause catalogue indexing") {
                activityCenter.isPaused.toggle()
            }

            Button(isRestarting ? "Restarting catalogue indexing..." : "Restart catalogue indexing") {
                Task { await restartCatalogueUpdate() }
            }
            .disabled(isRestarting)

            if snapshot.hasFailure {
                Button("Clear issue history") {
                    activityCenter.clearRecentFailures()
                }
            }
        }
    }

    @ViewBuilder
    private func catalogueRow(_ row: CatalogueRowModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusIndicator(for: row.status)
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.headline)

                Text(row.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusIndicator(for status: CatalogueRowStatus) -> some View {
        switch status {
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
        case .waitingForInternet:
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func restartCatalogueUpdate() async {
        guard !isRestarting else { return }

        isRestarting = true
        defer { isRestarting = false }

        do {
            activityCenter.isPaused = false
            activityCenter.clearRecentFailures()
            try await catalog.runBackgroundCatalogueIndex(forceRefresh: true)
        } catch {
            // Errors surface through the activity center itself.
        }
    }
}
