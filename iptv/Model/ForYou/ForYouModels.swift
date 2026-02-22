//
//  ForYouModels.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation

enum ForYouSectionStyle: Hashable {
    case hero
    case posterRail
    case continueWatchingRail
}

enum ForYouBadge: Hashable {
    case rating(String)
    case language(String)
    case isNew
    case series
}

struct ForYouItem: Identifiable, Hashable {
    var id: String {
        Self.makeID(contentType: contentType, videoID: video.id)
    }

    let video: Video
    let contentType: XtreamContentType
    let artworkURL: URL?
    let badge: ForYouBadge?
    let progress: WatchProgressSnapshot?

    static func makeID(contentType: XtreamContentType, videoID: Int) -> String {
        "\(contentType.rawValue):\(videoID)"
    }

    static func makeID(contentType: String, videoID: Int) -> String {
        "\(contentType):\(videoID)"
    }
}

extension ForYouItem {
    static func == (lhs: ForYouItem, rhs: ForYouItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.badge == rhs.badge &&
        lhs.progress == rhs.progress
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(badge)
        hasher.combine(progress)
    }
}

struct ForYouSection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let style: ForYouSectionStyle
    let items: [ForYouItem]
}

struct RecommendationContext {
    let providerFingerprint: String
    let watchRecords: [WatchActivityRecord]
    let vodCategories: [Category]
    let seriesCategories: [Category]
    let vodCatalog: [Category: [Video]]
    let seriesCatalog: [Category: [Video]]
}

extension ForYouItem {
    static func from(video: Video, progress: WatchProgressSnapshot? = nil, forceBadge: ForYouBadge? = nil) -> ForYouItem {
        let badge: ForYouBadge?
        if let forceBadge {
            badge = forceBadge
        } else if let rating = video.formattedRating {
            badge = .rating(rating)
        } else if video.xtreamContentType == .series {
            badge = .series
        } else if let language = video.language {
            badge = .language(language)
        } else {
            badge = nil
        }

        return ForYouItem(
            video: video,
            contentType: video.xtreamContentType,
            artworkURL: URL(string: video.coverImageURL ?? ""),
            badge: badge,
            progress: progress
        )
    }
}
