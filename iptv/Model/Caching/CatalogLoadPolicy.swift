//
//  CatalogLoadPolicy.swift
//  iptv
//
//  Created by Codex on 10.03.26.
//

import Foundation

enum CatalogLoadPolicy: Sendable, Equatable {
    case cachedOnly
    case cachedThenRefresh
    case refreshIfStale
    case refreshNow
}

enum CatalogCacheTTL {
    static let categories: TimeInterval = 6 * 60 * 60
    static let streams: TimeInterval = 60 * 60
    static let details: TimeInterval = 24 * 60 * 60
}
