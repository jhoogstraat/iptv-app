//
//  PlaybackBackend.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation

struct RendererAttachmentOwner: Equatable, Sendable {
    private(set) var ownerID: UUID?

    mutating func claim(_ ownerID: UUID) {
        self.ownerID = ownerID
    }

    @discardableResult
    mutating func release(_ ownerID: UUID) -> Bool {
        guard self.ownerID == ownerID else { return false }
        self.ownerID = nil
        return true
    }
}

enum PlaybackBackendID: String {
    case vlc
    case av
}

enum PlaybackState: Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case buffering
    case failed(String)
}

enum PlaybackEvent {
    case ready(duration: Double?)
    case playing
    case paused
    case buffering(Bool)
    case progress(currentTime: Double, duration: Double?)
    case advancedStateChanged
    case ended
    case failed(Error)
}

protocol PlaybackBackend: AnyObject {
    var id: PlaybackBackendID { get }
    var isAvailable: Bool { get }

    func canPlay(url: URL) -> Bool
    func load(url: URL, autoplay: Bool) throws
    func play()
    func pause()
    func togglePlayback()
    func stop()
    func seek(to seconds: Double)
    func events() -> AsyncStream<PlaybackEvent>

    // MARK: Advanced controls

    func capabilities() -> PlaybackCapabilities
    func audioTracks() -> [MediaTrack]
    func subtitleTracks() -> [MediaTrack]
    func qualityVariants() -> [QualityVariant]
    func chapterMarkers() -> [ChapterMarker]
    func availableOutputRoutes() -> [OutputRoute]
    func supportedAspectRatioModes() -> [PlayerAspectRatioMode]

    func selectAudioTrack(id: String)
    func selectSubtitleTrack(id: String)
    func selectQualityVariant(id: String) throws
    func setPlaybackSpeed(_ speed: Double)
    func setAspectRatio(_ mode: PlayerAspectRatioMode)
    func setAudioDelay(milliseconds: Int)
    func selectOutputRoute(id: String)
    func setVolume(_ value: Double)
    func setBrightness(_ value: Double)
}

extension PlaybackBackend {
    func capabilities() -> PlaybackCapabilities {
        .unsupported
    }

    func audioTracks() -> [MediaTrack] {
        []
    }

    func subtitleTracks() -> [MediaTrack] {
        []
    }

    func qualityVariants() -> [QualityVariant] {
        []
    }

    func chapterMarkers() -> [ChapterMarker] {
        []
    }

    func availableOutputRoutes() -> [OutputRoute] {
        []
    }

    func supportedAspectRatioModes() -> [PlayerAspectRatioMode] {
        [.fit]
    }

    func selectAudioTrack(id: String) {}
    func selectSubtitleTrack(id: String) {}
    func selectQualityVariant(id: String) throws {}
    func setPlaybackSpeed(_ speed: Double) {}
    func setAspectRatio(_ mode: PlayerAspectRatioMode) {}
    func setAudioDelay(milliseconds: Int) {}
    func selectOutputRoute(id: String) {}
    func setVolume(_ value: Double) {}
    func setBrightness(_ value: Double) {}
}

@MainActor
struct PlaybackBackendFactory {
    typealias BackendBuilder = () -> any PlaybackBackend

    private let builders: [BackendBuilder]

    init(builders: [BackendBuilder]) {
        self.builders = builders
    }

    init() {
        self.builders = [{ VLCPlaybackBackend() }, { AVPlaybackBackend() }]
    }

    func selectBackend(
        for url: URL,
        excluding excluded: Set<PlaybackBackendID> = [],
        preferred preferredID: PlaybackBackendID? = nil
    ) -> (any PlaybackBackend)? {
        let candidates = builders.map { $0() }
        let ordered = candidates.sorted { lhs, rhs in
            lhs.id == preferredID && rhs.id != preferredID
        }
        for backend in ordered {
            guard !excluded.contains(backend.id) else { continue }
            guard backend.isAvailable else { continue }
            guard backend.canPlay(url: url) else { continue }
            return backend
        }
        return nil
    }
}
