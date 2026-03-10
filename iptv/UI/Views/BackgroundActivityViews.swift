//
//  BackgroundActivityViews.swift
//  iptv
//
//  Created by Codex on 10.03.26.
//

import SwiftUI

struct BackgroundActivityIndicatorView: View {
    @Bindable var activityCenter: BackgroundActivityCenter
    @State private var isPresentingDetails = false

    var body: some View {
        if activityCenter.shouldShowIndicator {
            Button {
                isPresentingDetails = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbolName)
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titleText)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(activityCenter.summaryText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if activityCenter.activeCount > 0 {
                        Text("\(activityCenter.activeCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(.capsule)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isPresentingDetails) {
                NavigationStack {
                    BackgroundActivityDetailsScreen(activityCenter: activityCenter)
                }
            }
        }
    }

    private var symbolName: String {
        if activityCenter.isPaused {
            return "pause.circle.fill"
        }
        if activityCenter.hasFailures {
            return "exclamationmark.triangle.fill"
        }
        return "arrow.triangle.2.circlepath.circle.fill"
    }

    private var titleText: String {
        if activityCenter.isPaused {
            return "Background Work Paused"
        }
        if activityCenter.hasFailures, activityCenter.activeCount == 0 {
            return "Background Issue"
        }
        return "Background Activity"
    }
}

struct BackgroundActivityDetailsScreen: View {
    @Bindable var activityCenter: BackgroundActivityCenter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            controlsSection

            if activityCenter.activeList.isEmpty {
                Section("Active") {
                    Text("No active background tasks.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Active") {
                    ForEach(activityCenter.activeList) { activity in
                        activityRow(activity)
                    }
                }
            }

            if !activityCenter.recentList.isEmpty {
                Section("Recent") {
                    ForEach(activityCenter.recentList) { activity in
                        activityRow(activity)
                    }
                }
            }
        }
        .navigationTitle("Background Activity")
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
        Section {
            Toggle(isOn: $activityCenter.isPaused) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pause Background Work")
                    Text("Stops new cache warming, background refreshes, and indexing steps until resumed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if activityCenter.hasFailures {
                Button("Clear Recent Issues") {
                    activityCenter.clearRecentFailures()
                }
            }
        }
    }

    @ViewBuilder
    private func activityRow(_ activity: BackgroundActivity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(activity.title)
                    .font(.headline)
                Spacer()
                Text(statusText(for: activity))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(for: activity))
            }

            if let detail = activity.detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(activity.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let progress = activity.progressLabel {
                    Text(progress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(activity.updatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorDescription = activity.errorDescription, !errorDescription.isEmpty {
                Text(errorDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusText(for activity: BackgroundActivity) -> String {
        switch activity.state {
        case .running:
            return activityCenter.isPaused && activity.isPausable ? "Paused" : "Running"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    private func statusColor(for activity: BackgroundActivity) -> Color {
        switch activity.state {
        case .running:
            return activityCenter.isPaused && activity.isPausable ? .orange : .accentColor
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        }
    }
}
