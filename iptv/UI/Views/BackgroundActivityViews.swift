//
//  BackgroundActivityViews.swift
//  iptv
//
//  Created by Codex on 10.03.26.
//

import SwiftUI

private enum CatalogueArea: String, CaseIterable, Identifiable {
    case catalogue
    case movies
    case series
    case liveTV
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .catalogue:
            return "Catalogue"
        case .movies:
            return "Movies"
        case .series:
            return "Series"
        case .liveTV:
            return "Live TV"
        case .downloads:
            return "Downloads"
        }
    }

    var idleSubtitle: String {
        switch self {
        case .catalogue:
            return "Keeps browsing and search ready."
        case .movies:
            return "Checks movie categories and titles."
        case .series:
            return "Checks series categories and episodes."
        case .liveTV:
            return "Live TV updates are not part of this version yet."
        case .downloads:
            return "Shows offline download activity."
        }
    }

    var progressNoun: String {
        switch self {
        case .catalogue:
            return "catalogue steps"
        case .movies:
            return "movie categories"
        case .series:
            return "series categories"
        case .liveTV:
            return "TV categories"
        case .downloads:
            return "downloads"
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
}

private struct CatalogueRowModel: Identifiable {
    let area: CatalogueArea
    let status: CatalogueRowStatus
    let subtitle: String

    var id: String { area.id }
    var title: String { area.title }
}

struct BackgroundActivityIndicatorView: View {
    @Bindable var activityCenter: BackgroundActivityCenter
    @State private var isPresentingDetails = false

    var body: some View {
        if activityCenter.shouldShowIndicator {
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
            .accessibilityLabel(titleText)
            .accessibilityValue(activityCenter.summaryText)
            .sheet(isPresented: $isPresentingDetails) {
                NavigationStack {
                    BackgroundActivityDetailsScreen(activityCenter: activityCenter)
                }
            }
        }
    }

    @ViewBuilder
    private var indicatorIcon: some View {
        if activityCenter.isWaitingForInternet {
            Image(systemName: "wifi.slash")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.orange)
        } else if activityCenter.isPaused {
            Image(systemName: "pause.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.orange)
        } else if activityCenter.hasFailures, activityCenter.activeCount == 0 {
            Image(systemName: "exclamationmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.red)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var titleText: String {
        if activityCenter.isWaitingForInternet {
            return "Waiting for internet"
        }
        if activityCenter.isPaused {
            return "Updates paused"
        }
        if activityCenter.hasFailures, activityCenter.activeCount == 0 {
            return "Update needs attention"
        }
        return "Updates in progress"
    }
}

struct BackgroundActivityDetailsScreen: View {
    @Bindable var activityCenter: BackgroundActivityCenter
    @Environment(Catalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var isRestarting = false

    var body: some View {
        List {
            Section("Catalogue Status") {
                ForEach(catalogueRows) { row in
                    catalogueRow(row)
                }
            }

            if shouldShowDownloads {
                Section("Downloads") {
                    catalogueRow(downloadsRow)
                }
            }

            controlsSection
        }
        .navigationTitle("Catalogue Updates")
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

    private var catalogueRows: [CatalogueRowModel] {
        [
            makeRow(for: .catalogue),
            makeRow(for: .movies),
            makeRow(for: .series),
            makeRow(for: .liveTV)
        ]
    }

    private var downloadsRow: CatalogueRowModel {
        makeRow(for: .downloads)
    }

    private var shouldShowDownloads: Bool {
        let allRelated = relatedActivities(for: .downloads)
        return !allRelated.active.isEmpty || !allRelated.recent.isEmpty
    }

    private var controlsSection: some View {
        Section("Controls") {
            Button(activityCenter.isPaused ? "Resume updates" : "Pause updates") {
                activityCenter.isPaused.toggle()
            }

            Button(isRestarting ? "Restarting catalogue update..." : "Restart catalogue update") {
                Task { await restartCatalogueUpdate() }
            }
            .disabled(isRestarting)

            if activityCenter.hasFailures {
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
                    .fixedSize(horizontal: false, vertical: true)
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

    private func makeRow(for area: CatalogueArea) -> CatalogueRowModel {
        let related = relatedActivities(for: area)

        if let active = related.active.first {
            let status: CatalogueRowStatus
            if activityCenter.isWaitingForInternet, active.isPausable {
                status = .waitingForInternet
            } else if activityCenter.isPaused, active.isPausable {
                status = .paused
            } else {
                status = .running
            }
            return CatalogueRowModel(
                area: area,
                status: status,
                subtitle: subtitle(for: active, area: area)
            )
        }

        if let failed = related.recent.first(where: { $0.state == .failed }) {
            return CatalogueRowModel(
                area: area,
                status: .failure,
                subtitle: failureSubtitle(for: failed, area: area)
            )
        }

        if let completed = related.recent.first(where: { $0.state == .completed }) {
            return CatalogueRowModel(
                area: area,
                status: .success,
                subtitle: completionSubtitle(for: completed, area: area)
            )
        }

        if let cancelled = related.recent.first(where: { $0.state == .cancelled }) {
            return CatalogueRowModel(
                area: area,
                status: .idle,
                subtitle: friendlyDetail(cancelled.detail, fallback: area.idleSubtitle)
            )
        }

        return CatalogueRowModel(area: area, status: .idle, subtitle: area.idleSubtitle)
    }

    private func relatedActivities(for area: CatalogueArea) -> (active: [BackgroundActivity], recent: [BackgroundActivity]) {
        let active = activityCenter.activeList.filter { areas(for: $0).contains(area) }
        let recent = activityCenter.recentList.filter { areas(for: $0).contains(area) }
        return (active, recent)
    }

    private func areas(for activity: BackgroundActivity) -> Set<CatalogueArea> {
        let id = activity.id.lowercased()
        let source = activity.source.lowercased()
        var result: Set<CatalogueArea> = []

        if source == "downloads" {
            return [.downloads]
        }

        if id.hasPrefix("catalog-warmup:movies") {
            result.insert(.movies)
        } else if id.hasPrefix("catalog-warmup:series") {
            result.insert(.series)
        } else if id.hasPrefix("catalog-warmup:live") {
            result.insert(.liveTV)
        } else if id.hasPrefix("catalog-warmup:") {
            result.insert(.catalogue)
        }

        if id.hasPrefix("category-refresh:") {
            if id.contains("vodcategories") {
                result.insert(.movies)
            }
            if id.contains("seriescategories") {
                result.insert(.series)
            }
        }

        if id.hasPrefix("stream-refresh:") {
            if id.contains("|vod|") {
                result.insert(.movies)
            }
            if id.contains("|series|") {
                result.insert(.series)
            }
            if id.contains("|live|") {
                result.insert(.liveTV)
            }
        }

        if id.hasPrefix("vod-detail-refresh:") {
            result.insert(.movies)
        }

        if id.hasPrefix("series-detail-refresh:") {
            result.insert(.series)
        }

        if id.hasPrefix("search-coverage:") {
            if id.hasSuffix(":movies") {
                result.insert(.movies)
            } else if id.hasSuffix(":series") {
                result.insert(.series)
            } else {
                result.insert(.catalogue)
            }
        }

        if id.hasPrefix("search-index-rebuild:") {
            result.insert(.catalogue)
        }

        if result.isEmpty {
            result.insert(.catalogue)
        }

        return result
    }

    private func subtitle(for activity: BackgroundActivity, area: CatalogueArea) -> String {
        if activityCenter.isWaitingForInternet {
            return "Waiting for internet before continuing."
        }

        if area != .downloads,
           let current = activity.currentStep,
           let total = activity.totalSteps,
           total > 1 {
            return "\(min(current, total)) of \(total) \(area.progressNoun) updated"
        }

        return friendlyDetail(activity.detail, fallback: area.idleSubtitle)
    }

    private func completionSubtitle(for activity: BackgroundActivity, area: CatalogueArea) -> String {
        if let detail = activity.detail, !detail.isEmpty {
            return friendlyDetail(detail, fallback: "Up to date")
        }
        if area == .downloads {
            return "Downloads are up to date."
        }
        return "Up to date."
    }

    private func failureSubtitle(for activity: BackgroundActivity, area: CatalogueArea) -> String {
        if let detail = activity.detail, !detail.isEmpty {
            return friendlyDetail(detail, fallback: "Needs attention.")
        }
        if let errorDescription = activity.errorDescription, !errorDescription.isEmpty {
            return errorDescription
        }
        if area == .downloads {
            return "Downloads need attention."
        }
        return "This part of the catalogue needs attention."
    }

    private func friendlyDetail(_ detail: String?, fallback: String) -> String {
        guard let detail else { return fallback }

        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        return trimmed
            .replacingOccurrences(of: "Checking saved library data", with: "Organising saved titles for browsing")
            .replacingOccurrences(of: "Checking categories", with: "Looking for new categories")
            .replacingOccurrences(of: "Your library is ready", with: "Up to date")
            .replacingOccurrences(of: "Search is ready", with: "Up to date")
    }

    private func restartCatalogueUpdate() async {
        guard !isRestarting else { return }

        isRestarting = true
        defer { isRestarting = false }

        do {
            activityCenter.isPaused = false
            activityCenter.clearRecentFailures()
            try await catalog.refreshCurrentProvider()
            try await catalog.rebuildSearchIndexFromCachedMetadata()
        } catch {
            // Errors surface through the activity center itself.
        }
    }
}
