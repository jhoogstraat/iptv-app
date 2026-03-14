//
//  CatalogLoadPolicy.swift
//  iptv
//
//  Created by Codex on 10.03.26.
//

import Foundation

enum CatalogLoadPolicy: Sendable, Equatable {
    case cacheOnly
    case readThrough
    case forceRefresh
}
