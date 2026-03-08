//
//  MoviesScreenViewModel.swift
//  iptv
//
//  Created by Codex on 08.03.26.
//

import Foundation
import Observation

@MainActor
protocol MoviesBrowsingCatalog: AnyObject {
    func getCategories(for contentType: XtreamContentType, force: Bool) async throws
    func categories(for contentType: XtreamContentType) -> [Category]
    func getStreams(in category: Category, contentType: XtreamContentType, force: Bool) async throws
    func cachedVideos(in category: Category, contentType: XtreamContentType) -> [Video]?
}

extension Catalog: MoviesBrowsingCatalog {}

@MainActor
@Observable
final class MoviesScreenViewModel {
    enum Phase {
        case idle
        case fetching
        case error(Error)
        case done
    }

    let contentType: XtreamContentType

    var phase: Phase = .idle
    var queryText = "" {
        didSet { refreshBrowseResults() }
    }
    var selectedCategoryID: String?
    var browseSort: BrowseSort = .title {
        didSet { refreshBrowseResults() }
    }
    var browseResults: [Video] = []

    private let catalog: MoviesBrowsingCatalog

    init(contentType: XtreamContentType, catalog: MoviesBrowsingCatalog) {
        self.contentType = contentType
        self.catalog = catalog
    }

    var categories: [Category] {
        catalog.categories(for: contentType)
    }

    var selectedCategory: Category? {
        guard let selectedCategoryID else { return nil }
        return categories.first { $0.id == selectedCategoryID }
    }

    func reset() {
        phase = .idle
        selectedCategoryID = nil
        browseResults = []
    }

    func load(force: Bool = false) async {
        phase = .fetching

        do {
            try await catalog.getCategories(for: contentType, force: force)
            reconcileSelection()

            guard selectedCategory != nil else {
                browseResults = []
                phase = .done
                return
            }

            await loadSelectedCategory(force: force)
        } catch {
            phase = .error(error)
        }
    }

    func selectCategory(id: String?) async {
        guard selectedCategoryID != id else {
            refreshBrowseResults()
            return
        }

        selectedCategoryID = id
        await loadSelectedCategory()
    }

    func refreshBrowseResults() {
        guard let category = selectedCategory,
              let cachedVideos = catalog.cachedVideos(in: category, contentType: contentType) else {
            browseResults = []
            return
        }

        let trimmedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredVideos: [Video]
        if trimmedQuery.isEmpty {
            filteredVideos = cachedVideos
        } else {
            filteredVideos = cachedVideos.filter { video in
                video.name.localizedCaseInsensitiveContains(trimmedQuery)
            }
        }

        browseResults = sort(filteredVideos)
    }

    private func reconcileSelection() {
        guard !categories.isEmpty else {
            selectedCategoryID = nil
            return
        }

        if let selectedCategoryID,
           categories.contains(where: { $0.id == selectedCategoryID }) {
            return
        }

        selectedCategoryID = categories.first?.id
    }

    private func loadSelectedCategory(force: Bool = false) async {
        guard let category = selectedCategory else {
            browseResults = []
            phase = .done
            return
        }

        if !force, catalog.cachedVideos(in: category, contentType: contentType) != nil {
            refreshBrowseResults()
            phase = .done
            return
        }

        phase = .fetching
        browseResults = []

        do {
            try await catalog.getStreams(in: category, contentType: contentType, force: force)
            refreshBrowseResults()
            phase = .done
        } catch {
            phase = .error(error)
        }
    }

    private func sort(_ videos: [Video]) -> [Video] {
        switch browseSort {
        case .title:
            return videos.sorted { lhs, rhs in
                let titleOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }
                return lhs.id < rhs.id
            }
        case .newest:
            return videos.sorted { lhs, rhs in
                compare(
                    lhs,
                    rhs,
                    primary: { Self.parseDate($0.addedAtRaw)?.timeIntervalSinceReferenceDate ?? .leastNormalMagnitude }
                )
            }
        case .rating:
            return videos.sorted { lhs, rhs in
                compare(lhs, rhs, primary: { $0.rating ?? .leastNormalMagnitude })
            }
        }
    }

    private func compare(_ lhs: Video, _ rhs: Video, primary: (Video) -> Double) -> Bool {
        let leftPrimary = primary(lhs)
        let rightPrimary = primary(rhs)
        if leftPrimary != rightPrimary {
            return leftPrimary > rightPrimary
        }

        let leftRating = lhs.rating ?? .leastNormalMagnitude
        let rightRating = rhs.rating ?? .leastNormalMagnitude
        if leftRating != rightRating {
            return leftRating > rightRating
        }

        let leftAdded = Self.parseDate(lhs.addedAtRaw)?.timeIntervalSinceReferenceDate ?? .leastNormalMagnitude
        let rightAdded = Self.parseDate(rhs.addedAtRaw)?.timeIntervalSinceReferenceDate ?? .leastNormalMagnitude
        if leftAdded != rightAdded {
            return leftAdded > rightAdded
        }

        let titleOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        return lhs.id < rhs.id
    }

    private static func parseDate(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let seconds = Double(value), value.allSatisfy(\.isNumber) {
            return Date(timeIntervalSince1970: seconds)
        }

        let formats = [
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy/MM/dd",
            "dd-MM-yyyy",
            "MM/dd/yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}
