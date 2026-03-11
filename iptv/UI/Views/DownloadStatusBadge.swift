//
//  DownloadStatusBadge.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import SwiftUI

struct DownloadStatusBadge: View {
    let selection: DownloadSelection
    let showsTitle: Bool

    @Environment(DownloadCenter.self) private var downloadCenter
    @State private var isWorking = false

    init(selection: DownloadSelection, showsTitle: Bool = false) {
        self.selection = selection
        self.showsTitle = showsTitle
    }

    private var state: DownloadBadgeState {
        downloadCenter.badgeState(for: selection)
    }

    var body: some View {
        Button {
            performPrimaryAction()
        } label: {
            HStack(spacing: 8) {
                if case .downloading(let progress) = state, let progress {
                    ProgressView(value: progress)
                        .frame(width: 18)
                } else {
                    Image(systemName: state.symbolName)
                }

                if showsTitle {
                    Text(primaryLabel)
                        .lineLimit(1)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .contextMenu {
            if state != .completed {
                Button(downloadLabel) {
                    enqueue()
                }
            }

            if let groupID = downloadCenter.groupID(for: selection) {
                if state == .queued || state == .downloading(progress: nil) || isDownloading {
                    Button("Pause") {
                        pause(groupID)
                    }
                }

                if state == .paused {
                    Button("Resume") {
                        resume(groupID)
                    }
                }

                if state == .failed {
                    Button("Retry") {
                        retry(groupID)
                    }
                }

                Button(state == .completed ? "Remove Download" : "Remove") {
                    remove(groupID)
                }
            }
        }
        .accessibilityLabel(state.accessibilityLabel)
    }

    private var isDownloading: Bool {
        if case .downloading = state {
            return true
        }
        return false
    }

    private var primaryLabel: String {
        switch state {
        case .notDownloaded:
            return downloadLabel
        case .queued:
            return "Queued"
        case .downloading:
            return "Pause"
        case .paused:
            return "Resume"
        case .failed:
            return "Retry"
        case .completed:
            return "Downloaded"
        }
    }

    private var downloadLabel: String {
        switch selection {
        case .movie:
            return "Download"
        case .episode:
            return "Download Episode"
        case .season:
            return "Download Season"
        case .series:
            return "Download Series"
        }
    }

    private func performPrimaryAction() {
        switch state {
        case .notDownloaded:
            enqueue()
        case .queued, .downloading:
            guard let groupID = downloadCenter.groupID(for: selection) else { return }
            pause(groupID)
        case .paused:
            guard let groupID = downloadCenter.groupID(for: selection) else { return }
            resume(groupID)
        case .failed:
            guard let groupID = downloadCenter.groupID(for: selection) else { return }
            retry(groupID)
        case .completed:
            guard let groupID = downloadCenter.groupID(for: selection) else { return }
            remove(groupID)
        }
    }

    private func enqueue() {
        run {
            await downloadCenter.enqueue(selection)
        }
    }

    private func pause(_ id: String) {
        run {
            await downloadCenter.pause(groupOrAssetID: id)
        }
    }

    private func resume(_ id: String) {
        run {
            await downloadCenter.resume(groupOrAssetID: id)
        }
    }

    private func retry(_ id: String) {
        run {
            await downloadCenter.retry(groupOrAssetID: id)
        }
    }

    private func remove(_ id: String) {
        run {
            await downloadCenter.remove(groupOrAssetID: id)
        }
    }

    private func run(_ operation: @escaping @Sendable () async -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            await operation()
            await MainActor.run {
                isWorking = false
            }
        }
    }
}

