//
//  MediaPlaybackSourceResolver.swift
//  iptv
//
//  Created by Codex on 05.07.26.
//

import Foundation
import xtream_swift

/// Resolves persisted media rows into provider-specific playable stream URLs.
protocol MediaPlaybackSourceResolving {
    /// Returns a playable URL for the supplied local media and provider credentials.
    func playbackURL(for media: Media, provider: Provider) throws -> URL
}

/// Errors raised while converting local media state into a playable stream source.
enum MediaPlaybackSourceResolutionError: Equatable, LocalizedError {
    case missingActiveProvider
    case unsupportedCollection(MediaType)

    var errorDescription: String? {
        switch self {
        case .missingActiveProvider:
            return "Playback is unavailable because no active provider is configured."
        case .unsupportedCollection(let type):
            switch type {
            case .series:
                return "Open an episode to play this series. Series collections are not directly playable."
            case .movie:
                return "This movie cannot be resolved to a playable stream."
            case .episode:
                return "This episode cannot be resolved to a playable stream."
            case .live:
                return "This live channel cannot be resolved to a playable stream."
            }
        }
    }
}

/// Builds Xtream-compatible playback URLs from the locally persisted source identifier.
struct XtreamMediaPlaybackSourceResolver: MediaPlaybackSourceResolving {
    func playbackURL(for media: Media, provider: Provider) throws -> URL {
        switch media.type {
        case .movie:
            return playbackURL(for: media, provider: provider, contentType: .vod)
        case .episode:
            return playbackURL(for: media, provider: provider, contentType: .series)
        case .series:
            throw MediaPlaybackSourceResolutionError.unsupportedCollection(media.type)
        case .live:
            throw MediaPlaybackSourceResolutionError.unsupportedCollection(media.type)
        }
    }

    private func playbackURL(for media: Media, provider: Provider, contentType: Xtream.ContentType) -> URL {
        var url = XtreamEndpoint
            .playerAPIURL(from: provider.endpoint)
            .deletingLastPathComponent()

        url.appendPathComponent(contentType.playbackPathComponent)
        url.appendPathComponent(provider.username)
        url.appendPathComponent(provider.password)
        url.appendPathComponent(String(media.sourceID))

        return url
    }
}
