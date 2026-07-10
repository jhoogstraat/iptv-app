//
//  Tabs.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import Foundation

enum Tabs: CaseIterable, Equatable, Hashable, Identifiable {
    case home
    case movies
    case series
    case live
    
    case favorites
    case downloads
    case search
    case settings

    var id: Int {
        switch self {
            case .home: 2001
            case .movies: 2002
            case .series: 2003
            case .live: 2004
            case .favorites: 2005
            case .downloads: 2006
            case .search: 2007
            case .settings: 2008
        }
    }
    
    var name: String {
        switch self {
            case .home: String(localized: "For you", comment: "Tab title")
            case .movies: String(localized: "Movies", comment: "Tab title")
            case .series: String(localized: "Series", comment: "Tab title")
            case .live: String(localized: "Live", comment: "Tab title")
            case .favorites: String(localized: "Favorites", comment: "Tab title")
            case .downloads: String(localized: "Downloads", comment: "Tab title")
            case .search: String(localized: "Search", comment: "Tab title")
            case .settings: String(localized: "Settings", comment: "Tab title")
        }
    }
    
    var customizationID: String {
        switch self {
            case .home: "com.jhoogstraat.iptv.home"
            case .movies: "com.jhoogstraat.iptv.movies"
            case .series: "com.jhoogstraat.iptv.series"
            case .live: "com.jhoogstraat.iptv.live"
            case .favorites: "com.jhoogstraat.iptv.favorites"
            case .downloads: "com.jhoogstraat.iptv.downloads"
            case .search: "com.jhoogstraat.iptv.search"
            case .settings: "com.jhoogstraat.iptv.settings"
        }
    }

    var symbol: String {
        switch self {
            case .home: "sparkles"
            case .movies: "film"
            case .series: "tv"
            case .live: "dot.radiowaves.left.and.right"
            case .favorites: "heart"
            case .downloads: "arrow.down.circle"
            case .search: "magnifyingglass"
            case .settings: "gearshape"
        }
    }
}
