/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays a stable player shell with interchangeable renderers.
*/

import SwiftUI
import Foundation

/// A view that displays a full-window player with shared controls.
struct PlayerView: View {
    static let identifier = "PlayerView"

    @Environment(Player.self) private var player

    @State private var isShowingControls = true
    @State private var scrubTime: Double?
    @State private var hideControlsTask: Task<Void, Never>?

    private var sliderValue: Binding<Double> {
        Binding(
            get: { scrubTime ?? player.currentTime },
            set: { scrubTime = $0 }
        )
    }

    private var sliderRange: ClosedRange<Double> {
        let upper = max(player.duration ?? player.currentTime, 1)
        return 0...upper
    }

    var body: some View {
        ZStack {
            PlayerRendererContainer()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingControls.toggle()
                    }
                    scheduleAutoHideIfNeeded()
                }

            if isShowingControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .background(Color.black)
        .onAppear {
            scheduleAutoHideIfNeeded()
        }
        .onChange(of: player.isPlaying) { _, _ in
            scheduleAutoHideIfNeeded()
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    player.close()
                } label: {
                    Image(systemName: "xmark")
                }

                Spacer()

                if player.isBuffering {
                    Label("Buffering", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                }
            }

            Spacer()

            HStack(spacing: 32) {
                Button {
                    let newTime = max((scrubTime ?? player.currentTime) - 10, 0)
                    scrubTime = newTime
                    player.seek(to: newTime)
                } label: {
                    Image(systemName: "10.arrow.trianglehead.counterclockwise")
                }

                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }

                Button {
                    let newTime = min((scrubTime ?? player.currentTime) + 10, player.duration ?? ((scrubTime ?? player.currentTime) + 10))
                    scrubTime = newTime
                    player.seek(to: newTime)
                } label: {
                    Image(systemName: "10.arrow.trianglehead.clockwise")
                }
            }
            .font(.largeTitle)

            VStack(spacing: 8) {
                Slider(
                    value: sliderValue,
                    in: sliderRange,
                    onEditingChanged: { editing in
                        if editing {
                            hideControlsTask?.cancel()
                        } else {
                            let value = scrubTime ?? player.currentTime
                            player.seek(to: value)
                            scrubTime = nil
                            scheduleAutoHideIfNeeded()
                        }
                    }
                )

                HStack {
                    Text(formatTime(scrubTime ?? player.currentTime))
                    Spacer()
                    Text(formatTime(player.duration ?? 0))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.currentItem?.name ?? "No item loaded")
                        .font(.headline)
                    Text("Backend: \(player.activeBackendID?.rawValue.uppercased() ?? "N/A")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let errorMessage = player.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .foregroundStyle(.white)
        .background(.black.opacity(0.35))
        .contentShape(Rectangle())
        .onTapGesture {
            scheduleAutoHideIfNeeded()
        }
    }

    private func scheduleAutoHideIfNeeded() {
        hideControlsTask?.cancel()
        guard player.isPlaying else { return }

        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                isShowingControls = false
            }
        }
    }

    private func formatTime(_ rawSeconds: Double) -> String {
        let totalSeconds = max(0, Int(rawSeconds.rounded()))
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview(traits: .previewData) {
    PlayerView()
}
