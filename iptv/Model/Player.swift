/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model object that manages stream playback and backend fallback.
*/

import AVFoundation
import Foundation
import Observation
import OSLog

/// The presentation modes the player supports.
enum Presentation {
    /// Presents the player as a child of a parent user interface.
    case inline
    /// Presents the player in full-window exclusive mode.
    case fullWindow
}

@MainActor
@Observable
final class Player {
    private(set) var playbackState: PlaybackState = .idle
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var isPlaybackComplete = false
    private(set) var presentation: Presentation = .inline
    private(set) var currentItem: Video?
    private(set) var currentURL: URL?
    private(set) var currentTime: Double = 0
    private(set) var duration: Double?
    private(set) var errorMessage: String?
    private(set) var activeBackendID: PlaybackBackendID?
    private(set) var rendererRevision = 0
    private(set) var shouldAutoPlay = true

    var progressFraction: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var formattedCurrentTime: String {
        Self.formatTime(currentTime)
    }

    var formattedDuration: String {
        Self.formatTime(duration ?? 0)
    }

    private let backendFactory: PlaybackBackendFactory
    private var backend: (any PlaybackBackend)?
    private var eventTask: Task<Void, Never>?
    private var didFallbackForCurrentItem = false

    init(backendFactory: PlaybackBackendFactory? = nil) {
        self.backendFactory = backendFactory ?? PlaybackBackendFactory()
    }

    var vlcRenderer: VLCPlayerReference? {
        (backend as? VLCPlaybackBackend)?.player
    }

    var avRenderer: AVPlayer? {
        (backend as? AVPlaybackBackend)?.player
    }

    /// Loads a stream for playback in the requested presentation.
    func load(_ video: Video, _ url: URL, presentation: Presentation, autoplay: Bool = true) {
        currentItem = video
        currentURL = url
        shouldAutoPlay = autoplay
        didFallbackForCurrentItem = false
        isPlaybackComplete = false
        errorMessage = nil
        currentTime = 0
        duration = nil
        playbackState = .loading
        self.presentation = presentation

        do {
            try activateBackend(for: video, url: url)
            try backend?.load(url: url, autoplay: autoplay)
            logger.info("Playback started with backend \(self.activeBackendID?.rawValue ?? "unknown", privacy: .public)")
        } catch {
            processTerminalFailure(error)
        }
    }

    /// Clears any loaded media and resets the player model to its default state.
    func reset() {
        eventTask?.cancel()
        eventTask = nil
        backend?.stop()
        backend = nil
        activeBackendID = nil
        rendererRevision += 1

        currentItem = nil
        currentURL = nil
        shouldAutoPlay = true
        didFallbackForCurrentItem = false
        isPlaybackComplete = false
        isPlaying = false
        isBuffering = false
        currentTime = 0
        duration = nil
        errorMessage = nil
        playbackState = .idle
        presentation = .inline
    }

    func close() {
        reset()
    }

    // MARK: - Transport control

    func play() {
        backend?.play()
    }

    func pause() {
        backend?.pause()
    }

    func togglePlayback() {
        backend?.togglePlayback()
    }

    func seek(to seconds: Double) {
        backend?.seek(to: seconds)
    }

    // MARK: - Internals

    private func activateBackend(for video: Video, url: URL, excluding excluded: Set<PlaybackBackendID> = []) throws {
        guard let selected = backendFactory.selectBackend(
            for: url,
            contentType: video.contentType,
            containerExtension: video.containerExtension,
            excluding: excluded
        ) else {
            throw PlaybackRuntimeError.noRendererAvailable
        }

        eventTask?.cancel()
        eventTask = nil
        backend?.stop()

        backend = selected
        activeBackendID = selected.id
        rendererRevision += 1
        bindEvents(for: selected)
    }

    private func bindEvents(for backend: any PlaybackBackend) {
        let backendID = backend.id
        eventTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in backend.events() {
                if Task.isCancelled { return }
                self.handle(event, from: backendID)
            }
        }
    }

    private func handle(_ event: PlaybackEvent, from backendID: PlaybackBackendID) {
        switch event {
        case .ready(let duration):
            self.duration = duration ?? self.duration
            playbackState = .ready
            isBuffering = false
            errorMessage = nil

        case .playing:
            isPlaying = true
            isBuffering = false
            playbackState = .playing

        case .paused:
            isPlaying = false
            if case .failed = playbackState {
                return
            }
            playbackState = .paused

        case .buffering(let buffering):
            isBuffering = buffering
            if buffering {
                playbackState = .buffering
            }

        case .progress(let currentTime, let duration):
            self.currentTime = max(0, currentTime)
            if let duration, duration > 0 {
                self.duration = duration
            }

        case .ended:
            isPlaying = false
            isBuffering = false
            isPlaybackComplete = true
            playbackState = .paused

        case .failed(let error):
            processFailure(error, from: backendID)
        }
    }

    private func processFailure(_ error: Error, from backendID: PlaybackBackendID) {
        logger.error("Playback backend \(backendID.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")

        guard backendID == .vlc,
              !didFallbackForCurrentItem,
              let currentItem,
              let currentURL
        else {
            processTerminalFailure(error)
            return
        }

        didFallbackForCurrentItem = true
        logger.info("Attempting automatic playback fallback to AV backend.")

        do {
            try activateBackend(for: currentItem, url: currentURL, excluding: [.vlc])
            try backend?.load(url: currentURL, autoplay: shouldAutoPlay)
            playbackState = .loading
            errorMessage = nil
        } catch {
            processTerminalFailure(error)
        }
    }

    private func processTerminalFailure(_ error: Error) {
        isPlaying = false
        isBuffering = false
        let message = error.localizedDescription
        errorMessage = message
        playbackState = .failed(message)
        logger.error("Terminal playback failure: \(message, privacy: .public)")
    }

    private static func formatTime(_ rawSeconds: Double) -> String {
        guard rawSeconds.isFinite else { return "00:00" }
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
