//
//  Tabs.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import Foundation

enum Tabs: Equatable, Hashable, Identifiable {
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
        return "com.jhoogstraat.iptv." + self.name
    }

    var symbol: String {
        switch self {
            case .home: "play"
            case .movies: "list.and.film"
            case .series: "list.and.film"
            case .live: "list.and.film"
            case .favorites: "heart"
            case .downloads: "list.and.film"
            case .search: "magnifyingglass"
            case .settings: "list.and.film"
        }
    }
}
