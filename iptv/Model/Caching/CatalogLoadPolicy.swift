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
    case refreshNow
}
