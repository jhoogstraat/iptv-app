//
//  PlaybackBackend.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation

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
    case ended
    case failed(Error)
}

protocol PlaybackBackend: AnyObject {
    var id: PlaybackBackendID { get }
    var isAvailable: Bool { get }

    func canPlay(url: URL, contentType: String, containerExtension: String?) -> Bool
    func load(url: URL, autoplay: Bool) throws
    func play()
    func pause()
    func togglePlayback()
    func stop()
    func seek(to seconds: Double)
    func events() -> AsyncStream<PlaybackEvent>
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
        contentType: String,
        containerExtension: String?,
        excluding excluded: Set<PlaybackBackendID> = []
    ) -> (any PlaybackBackend)? {
        for builder in builders {
            let backend = builder()
            guard !excluded.contains(backend.id), backend.isAvailable else { continue }
            guard backend.canPlay(url: url, contentType: contentType, containerExtension: containerExtension) else { continue }
            return backend
        }
        return nil
    }
}
