//
//  PlayerAdvancedModels.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import Foundation
import CoreGraphics

enum MediaTrackKind: String, Codable, Sendable {
    case audio
    case subtitle
}

struct MediaTrack: Identifiable, Hashable, Sendable {
    static let subtitleOffID = "__subtitle_off__"

    let id: String
    let kind: MediaTrackKind
    let languageCode: String?
    let label: String
    let isDefault: Bool
    let isForced: Bool
}

struct QualityVariant: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let bitrate: Int?
    let resolution: String?
    let frameRate: Double?
    let isAuto: Bool

    static let auto = QualityVariant(
        id: "auto",
        label: "Auto",
        bitrate: nil,
        resolution: nil,
        frameRate: nil,
        isAuto: true
    )
}

struct ChapterMarker: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let startSeconds: Double
}

struct OutputRoute: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isActive: Bool
}

struct PlaybackCapabilities: Equatable, Sendable {
    var supportsAudioTracks: Bool
    var supportsSubtitles: Bool
    var supportsQualitySelection: Bool
    var supportsChapterMarkers: Bool
    var supportsOutputRouteSelection: Bool
    var supportsAudioDelay: Bool
    var supportsBrightness: Bool

    static let unsupported = PlaybackCapabilities(
        supportsAudioTracks: false,
        supportsSubtitles: false,
        supportsQualitySelection: false,
        supportsChapterMarkers: false,
        supportsOutputRouteSelection: false,
        supportsAudioDelay: false,
        supportsBrightness: false
    )
}

enum PlayerAspectRatioMode: String, CaseIterable, Identifiable, Sendable {
    case fit
    case fill
    case sixteenByNine
    case fourByThree
    case original

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fit:
            "Fit"
        case .fill:
            "Fill"
        case .sixteenByNine:
            "16:9"
        case .fourByThree:
            "4:3"
        case .original:
            "Original"
        }
    }

    var fixedAspectRatio: CGFloat? {
        switch self {
        case .sixteenByNine:
            16.0 / 9.0
        case .fourByThree:
            4.0 / 3.0
        default:
            nil
        }
    }
}

enum SleepTimerOption: String, CaseIterable, Identifiable, Sendable {
    case off
    case minutes15
    case minutes30
    case minutes60
    case endOfItem

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:
            "Off"
        case .minutes15:
            "15m"
        case .minutes30:
            "30m"
        case .minutes60:
            "60m"
        case .endOfItem:
            "End of item"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .off, .endOfItem:
            nil
        case .minutes15:
            15 * 60
        case .minutes30:
            30 * 60
        case .minutes60:
            60 * 60
        }
    }
}
