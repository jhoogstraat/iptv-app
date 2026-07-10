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
    case insecureProviderTransport
    case providerCredentialsUnavailable
    case unsupportedCollection(MediaType)

    var errorDescription: String? {
        switch self {
        case .missingActiveProvider:
            return "Playback is unavailable because no active provider is configured."
        case .insecureProviderTransport:
            return "Playback is blocked because this provider is not using an approved secure connection."
        case .providerCredentialsUnavailable:
            return "Playback credentials are unavailable. Re-enter the provider password in Settings and try again."
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
            return playbackURL(for: media, provider: provider, contentType: .live)
        }
    }

    private func playbackURL(for media: Media, provider: Provider, contentType: Xtream.ContentType) -> URL {
        let baseURL = XtreamEndpoint
            .playerAPIURL(from: provider.endpoint)
            .deletingLastPathComponent()
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathSegments = [
            contentType.playbackPathComponent,
            provider.username,
            provider.password,
            streamPathComponent(for: media),
        ]
        let encodedPath = pathSegments.map(percentEncodedPathSegment).joined(separator: "/")
        components.percentEncodedPath = "/" + ([basePath, encodedPath].filter { !$0.isEmpty }).joined(separator: "/")
        return components.url ?? baseURL
    }

    /// Encodes a value as exactly one RFC 3986 path segment. Foundation's
    /// `urlPathAllowed` set intentionally includes "/", which is unsafe for credentials.
    private func percentEncodedPathSegment(_ value: String) -> String {
        value.utf8.map { byte in
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x2E, 0x5F, 0x7E:
                return String(UnicodeScalar(byte))
            default:
                return String(format: "%%%02X", byte)
            }
        }.joined()
    }

    private func streamPathComponent(for media: Media) -> String {
        guard let containerExtension = media.containerExtension?.trimmingCharacters(in: .whitespacesAndNewlines),
              !containerExtension.isEmpty
        else {
            return String(media.sourceID)
        }

        let normalizedExtension = containerExtension.hasPrefix(".")
            ? String(containerExtension.dropFirst())
            : containerExtension
        return "\(media.sourceID).\(normalizedExtension)"
    }
}
