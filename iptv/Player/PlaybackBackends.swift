//
//  PlaybackBackends.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import AVFoundation
import Foundation

#if canImport(VLCKit)
import VLCKit
#endif

enum PlaybackRuntimeError: LocalizedError {
    case backendFailure(String)
    case noRendererAvailable

    var errorDescription: String? {
        switch self {
        case .backendFailure(let message):
            return message
        case .noRendererAvailable:
            return "No supported playback backend is available for this stream."
        }
    }
}


#if canImport(VLCKit)
@MainActor
final class VLCPlaybackBackend: NSObject, PlaybackBackend {
    let id: PlaybackBackendID = .vlc
    let player: VLCPlayerReference = VLCMediaPlayer()

    var isAvailable: Bool { true }

    private let stream: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private var progressTimer: Timer?

    override init() {
        var continuation: AsyncStream<PlaybackEvent>.Continuation?
        self.stream = AsyncStream<PlaybackEvent> { continuation = $0 }
        self.continuation = continuation!
        super.init()
        player.delegate = self
    }

    func canPlay(url: URL, contentType: String, containerExtension: String?) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        return ["http", "https", "rtsp", "file"].contains(scheme) || !scheme.isEmpty
    }

    func load(url: URL, autoplay: Bool) throws {
        player.media = VLCMedia(url: url)
        continuation.yield(.ready(duration: mediaDuration()))
        if autoplay {
            play()
        }
        startProgressTimer()
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayback() {
        player.isPlaying ? player.pause() : player.play()
    }

    func stop() {
        stopProgressTimer()
        player.stop()
    }

    func seek(to seconds: Double) {
        let milliseconds = Int32(max(0, seconds) * 1000.0)
        player.time = VLCTime(int: milliseconds)
    }

    func events() -> AsyncStream<PlaybackEvent> {
        stream
    }

    private func mediaDuration() -> Double? {
        let value = Double(player.media?.length.intValue ?? 0) / 1000.0
        return value > 0 ? value : nil
    }

    private func currentTime() -> Double {
        Double(player.time.intValue) / 1000.0
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.continuation.yield(.progress(currentTime: self.currentTime(), duration: self.mediaDuration()))
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

@MainActor
extension VLCPlaybackBackend: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        switch newState {
        case .opening:
            continuation.yield(.buffering(true))
        case .buffering:
            continuation.yield(.buffering(true))
        case .playing:
            continuation.yield(.buffering(false))
            continuation.yield(.playing)
        case .paused:
            continuation.yield(.paused)
        case .stopped:
            if let duration = mediaDuration(), duration > 0, currentTime() >= duration - 0.5 {
                continuation.yield(.ended)
            } else {
                continuation.yield(.paused)
            }
        case .stopping:
            continuation.yield(.buffering(true))
        case .error:
            continuation.yield(.failed(PlaybackRuntimeError.backendFailure("VLC failed to play this stream.")))
        default:
            break
        }
    }
}
#else
final class VLCPlaybackBackend: NSObject, PlaybackBackend {
    let id: PlaybackBackendID = .vlc
    let player: VLCPlayerReference? = nil

    var isAvailable: Bool { false }

    func canPlay(url: URL, contentType: String, containerExtension: String?) -> Bool {
        false
    }

    func load(url: URL, autoplay: Bool) throws {
        throw PlaybackRuntimeError.noRendererAvailable
    }

    func play() {}
    func pause() {}
    func togglePlayback() {}
    func stop() {}
    func seek(to seconds: Double) {}
    func events() -> AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
#endif

@MainActor
final class AVPlaybackBackend: NSObject, PlaybackBackend {
    let id: PlaybackBackendID = .av
    let player = AVPlayer()

    var isAvailable: Bool { true }

    private let stream: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    private var timeObserver: Any?
    private var playerStateObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var failedObserver: NSObjectProtocol?
    private var endedObserver: NSObjectProtocol?

    override init() {
        var continuation: AsyncStream<PlaybackEvent>.Continuation?
        self.stream = AsyncStream<PlaybackEvent> { continuation = $0 }
        self.continuation = continuation!
        super.init()
        observePlayerState()
    }

    func canPlay(url: URL, contentType: String, containerExtension: String?) -> Bool {
        let supportedExtensions: Set<String> = [
            "m3u8", "mp4", "m4v", "mov", "mp3", "aac", "ac3", "wav"
        ]

        guard let ext = containerExtension?.lowercased(), !ext.isEmpty else {
            return false
        }
        return supportedExtensions.contains(ext)
    }

    func load(url: URL, autoplay: Bool) throws {
        cleanupItemObservers()

        let item = AVPlayerItem(url: url)
        observeItemStatus(item)
        observeItemNotifications(item)
        player.replaceCurrentItem(with: item)

        if autoplay {
            play()
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayback() {
        player.rate > 0 ? player.pause() : player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        cleanupItemObservers()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time)
    }

    func events() -> AsyncStream<PlaybackEvent> {
        stream
    }

    private func observePlayerState() {
        playerStateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            switch player.timeControlStatus {
            case .playing:
                self.continuation.yield(.buffering(false))
                self.continuation.yield(.playing)
            case .paused:
                self.continuation.yield(.paused)
            case .waitingToPlayAtSpecifiedRate:
                self.continuation.yield(.buffering(true))
            @unknown default:
                break
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let current = max(0, time.seconds)
            let duration = self.currentDuration()
            self.continuation.yield(.progress(currentTime: current, duration: duration))
        }
    }

    private func observeItemStatus(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            switch item.status {
            case .readyToPlay:
                self.continuation.yield(.ready(duration: self.currentDuration()))
            case .failed:
                self.continuation.yield(.failed(item.error ?? PlaybackRuntimeError.backendFailure("AVPlayer failed to load this stream.")))
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    private func observeItemNotifications(_ item: AVPlayerItem) {
        let center = NotificationCenter.default
        failedObserver = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self.continuation.yield(.failed(error ?? PlaybackRuntimeError.backendFailure("AVPlayer failed during playback.")))
        }

        endedObserver = center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.continuation.yield(.ended)
        }
    }

    private func currentDuration() -> Double? {
        guard let item = player.currentItem else { return nil }
        let seconds = item.duration.seconds
        guard seconds.isFinite && seconds > 0 else { return nil }
        return seconds
    }

    private func cleanupItemObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
            self.failedObserver = nil
        }
        if let endedObserver {
            NotificationCenter.default.removeObserver(endedObserver)
            self.endedObserver = nil
        }
    }

    private func cleanupObservers() {
        cleanupItemObservers()
        playerStateObservation?.invalidate()
        playerStateObservation = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}
