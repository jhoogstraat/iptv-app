//
//  SearchModels.swift
//  iptv
//
//  Created by Codex on 24.02.26.
//

import Foundation

enum SearchMediaScope: String, CaseIterable, Codable, Sendable {
    case all
    case movies
    case series

    var displayName: String {
        switch self {
        case .all:
            "All"
        case .movies:
            "Movies"
        case .series:
            "Series"
        }
    }

    var acceptedContentTypes: Set<XtreamContentType> {
        switch self {
        case .all:
            [.vod, .series]
        case .movies:
            [.vod]
        case .series:
            [.series]
        }
    }
}

enum SearchSort: String, CaseIterable, Codable, Sendable {
    case relevance
    case newest
    case rating
    case title

    var displayName: String {
        switch self {
        case .relevance:
            "Relevance"
        case .newest:
            "Newest"
        case .rating:
            "Rating"
        case .title:
            "Title"
        }
    }
}

enum BrowseSort: String, CaseIterable, Codable, Sendable {
    case title
    case newest
    case rating

    var displayName: String {
        switch self {
        case .title:
            "Title"
        case .newest:
            "Newest"
        case .rating:
            "Rating"
        }
    }

    var searchSort: SearchSort {
        switch self {
        case .title:
            .title
        case .newest:
            .newest
        case .rating:
            .rating
        }
    }
}

enum SearchAddedWindow: String, CaseIterable, Codable, Sendable {
    case any
    case days30
    case days90
    case year1

    var displayName: String {
        switch self {
        case .any:
            "Any time"
        case .days30:
            "Last 30 days"
        case .days90:
            "Last 90 days"
        case .year1:
            "Last year"
        }
    }

    nonisolated var dayCount: Int? {
        switch self {
        case .any:
            nil
        case .days30:
            30
        case .days90:
            90
        case .year1:
            365
        }
    }
}

enum SearchMatchedField: String, Hashable, Sendable {
    case titlePrefix
    case titleContains
    case genre
    case language
    case category
}

struct SearchFilters: Hashable, Sendable {
    var minRating: Double?
    var maxRating: Double?
    var genres: Set<String>
    var languages: Set<String>
    var categoryIDs: Set<String>
    var addedWindow: SearchAddedWindow

    static let `default` = SearchFilters(
        minRating: nil,
        maxRating: nil,
        genres: [],
        languages: [],
        categoryIDs: [],
        addedWindow: .any
    )
}

struct SearchQuery: Hashable, Sendable {
    var text: String
    var scope: SearchMediaScope
    var filters: SearchFilters
    var sort: SearchSort

    init(
        text: String,
        scope: SearchMediaScope = .all,
        filters: SearchFilters = .default,
        sort: SearchSort = .relevance
    ) {
        self.text = text
        self.scope = scope
        self.filters = filters
        self.sort = sort
    }
}

struct SearchResultItem: Identifiable {
    let video: Video
    let scope: SearchMediaScope
    let score: Double
    let matchedFields: Set<SearchMatchedField>

    var id: String {
        "\(video.xtreamContentType.rawValue):\(video.id)"
    }
}

struct SearchIndexProgress: Hashable, Sendable {
    let indexedCategories: Int
    let totalCategories: Int
    let scope: SearchMediaScope

    var fractionComplete: Double {
        guard totalCategories > 0 else { return 1 }
        return min(max(Double(indexedCategories) / Double(totalCategories), 0), 1)
    }

    var isComplete: Bool {
        totalCategories > 0 && indexedCategories >= totalCategories
    }
}

struct SearchFacetValues: Hashable, Sendable {
    let genres: [String]
    let languages: [String]
}
