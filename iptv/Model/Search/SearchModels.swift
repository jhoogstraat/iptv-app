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

    nonisolated var acceptedContentTypes: Set<XtreamContentType> {
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

struct SearchVideoSummary: Identifiable, Hashable, Sendable {
    let videoID: Int
    let name: String
    let containerExtension: String
    let contentType: String
    let coverImageURL: String?
    let artworkURL: URL?
    let rating: Double?
    let displayRating: String?
    let addedAtRaw: String?
    let language: String?

    var id: String {
        "\(contentType):\(videoID)"
    }

    var xtreamContentType: XtreamContentType {
        switch contentType {
        case XtreamContentType.series.rawValue:
            .series
        case XtreamContentType.live.rawValue:
            .live
        default:
            .vod
        }
    }

    func asVideo() -> Video {
        Video(
            id: videoID,
            name: name,
            containerExtension: containerExtension,
            contentType: contentType,
            coverImageURL: coverImageURL,
            tmdbId: nil,
            rating: rating,
            addedAtRaw: addedAtRaw
        )
    }
}

struct SearchResultItem: Identifiable {
    let summary: SearchVideoSummary
    let scope: SearchMediaScope
    let score: Double
    let matchedFields: Set<SearchMatchedField>

    var id: String {
        "\(summary.xtreamContentType.rawValue):\(summary.videoID)"
    }

    var video: Video {
        summary.asVideo()
    }
}

struct SearchResultRowState: Identifiable {
    let result: SearchResultItem
    let isFavorite: Bool

    var id: String {
        result.id
    }

    var summary: SearchVideoSummary {
        result.summary
    }

    var scope: SearchMediaScope {
        result.scope
    }

    func updatingFavorite(_ isFavorite: Bool) -> SearchResultRowState {
        SearchResultRowState(result: result, isFavorite: isFavorite)
    }
}

struct CatalogueSyncProgress: Hashable, Sendable {
    let syncedCategories: Int
    let totalCategories: Int
    let scope: SearchMediaScope

    nonisolated init(syncedCategories: Int, totalCategories: Int, scope: SearchMediaScope) {
        self.syncedCategories = syncedCategories
        self.totalCategories = totalCategories
        self.scope = scope
    }

    nonisolated init(indexedCategories: Int, totalCategories: Int, scope: SearchMediaScope) {
        self.init(syncedCategories: indexedCategories, totalCategories: totalCategories, scope: scope)
    }

    var fractionComplete: Double {
        guard totalCategories > 0 else { return 1 }
        return min(max(Double(syncedCategories) / Double(totalCategories), 0), 1)
    }

    nonisolated var indexedCategories: Int {
        syncedCategories
    }

    var isComplete: Bool {
        totalCategories > 0 && syncedCategories >= totalCategories
    }
}

typealias SearchIndexProgress = CatalogueSyncProgress

struct SearchFacetValues: Hashable, Sendable {
    let genres: [String]
    let languages: [String]
}

struct ProviderCatalogueSummary: Hashable, Sendable {
    let movieCount: Int
    let seriesCount: Int
    let syncedMovieCategories: Int
    let totalMovieCategories: Int
    let syncedSeriesCategories: Int
    let totalSeriesCategories: Int

    nonisolated init(
        movieCount: Int,
        seriesCount: Int,
        syncedMovieCategories: Int,
        totalMovieCategories: Int,
        syncedSeriesCategories: Int,
        totalSeriesCategories: Int
    ) {
        self.movieCount = movieCount
        self.seriesCount = seriesCount
        self.syncedMovieCategories = syncedMovieCategories
        self.totalMovieCategories = totalMovieCategories
        self.syncedSeriesCategories = syncedSeriesCategories
        self.totalSeriesCategories = totalSeriesCategories
    }

    nonisolated init(
        movieCount: Int,
        seriesCount: Int,
        indexedMovieCategories: Int,
        totalMovieCategories: Int,
        indexedSeriesCategories: Int,
        totalSeriesCategories: Int
    ) {
        self.init(
            movieCount: movieCount,
            seriesCount: seriesCount,
            syncedMovieCategories: indexedMovieCategories,
            totalMovieCategories: totalMovieCategories,
            syncedSeriesCategories: indexedSeriesCategories,
            totalSeriesCategories: totalSeriesCategories
        )
    }

    var isComplete: Bool {
        syncedMovieCategories >= totalMovieCategories &&
        syncedSeriesCategories >= totalSeriesCategories &&
        totalMovieCategories > 0 &&
        totalSeriesCategories > 0
    }

    nonisolated var indexedMovieCategories: Int {
        syncedMovieCategories
    }

    nonisolated var indexedSeriesCategories: Int {
        syncedSeriesCategories
    }
}
