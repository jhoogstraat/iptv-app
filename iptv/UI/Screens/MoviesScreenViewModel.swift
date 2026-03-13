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
    func getCategories(for contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws
    func categories(for contentType: XtreamContentType) -> [Category]
    func getStreams(in category: Category, contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws
    func cachedVideos(in category: Category, contentType: XtreamContentType) -> [Video]?
}

extension Catalog: MoviesBrowsingCatalog {}

struct MoviesBrowseItem: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let artworkURL: URL?
    let ratingText: String?
    let languageText: String?
}

private struct MoviesBrowseSourceItem: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let normalizedTitle: String
    let artworkURL: URL?
    let ratingText: String?
    let languageText: String?
    let ratingValue: Double
    let addedAtReferenceDate: Double
}

@MainActor
@Observable
final class MoviesScreenViewModel {
    private enum DerivationPolicy {
        static let synchronousThreshold = 250
    }

    struct CategoryMenuSection: Identifiable {
        let title: String?
        let items: [CategoryMenuItem]

        var id: String {
            title ?? "__ungrouped__"
        }
    }

    struct CategoryMenuItem: Identifiable {
        let category: Category
        let title: String

        var id: String {
            category.id
        }
    }

    enum Phase {
        case idle
        case fetching
        case error(Error)
        case done
    }

    let contentType: XtreamContentType

    var phase: Phase = .idle
    var queryText = "" {
        didSet { scheduleBrowseResultsRefresh() }
    }
    var selectedCategoryID: String?
    var browseSort: BrowseSort = .title {
        didSet { scheduleBrowseResultsRefresh() }
    }
    var browseResults: [MoviesBrowseItem] = []

    private let catalog: MoviesBrowsingCatalog
    private var sourceItems: [MoviesBrowseSourceItem] = []
    private var videosByID: [Int: Video] = [:]
    private var browseResultsTask: Task<Void, Never>?
    private var browseResultsRevision = UUID()

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

    var categoryMenuSections: [CategoryMenuSection] {
        var ungroupedItems: [CategoryMenuItem] = []
        var groupedItemsByLanguage: [String: [CategoryMenuItem]] = [:]
        var languageOrder: [String] = []

        for category in categories {
            let item = CategoryMenuItem(category: category, title: category.groupedDisplayName)

            guard let languageCode = category.languageGroupCode else {
                ungroupedItems.append(item)
                continue
            }

            if groupedItemsByLanguage[languageCode] == nil {
                languageOrder.append(languageCode)
            }
            groupedItemsByLanguage[languageCode, default: []].append(item)
        }

        var sections: [CategoryMenuSection] = []
        if !ungroupedItems.isEmpty {
            sections.append(CategoryMenuSection(title: nil, items: ungroupedItems))
        }

        for languageCode in languageOrder {
            guard let items = groupedItemsByLanguage[languageCode], !items.isEmpty else { continue }
            sections.append(CategoryMenuSection(title: languageCode, items: items))
        }

        return sections
    }

    func reset() {
        browseResultsTask?.cancel()
        browseResultsRevision = UUID()
        phase = .idle
        selectedCategoryID = nil
        sourceItems = []
        videosByID = [:]
        browseResults = []
    }

    func load(policy: CatalogLoadPolicy = .cachedThenRefresh) async {
        phase = .fetching

        do {
            try await catalog.getCategories(for: contentType, policy: policy)
            reconcileSelection()

            guard selectedCategory != nil else {
                browseResults = []
                phase = .done
                return
            }

            await loadSelectedCategory(policy: policy)
        } catch {
            phase = .error(error)
        }
    }

    func selectCategory(id: String?) async {
        guard selectedCategoryID != id else {
            await refreshBrowseResultsNow()
            return
        }

        selectedCategoryID = id

        guard let category = selectedCategory else {
            sourceItems = []
            videosByID = [:]
            browseResults = []
            phase = .done
            return
        }

        if let cachedVideos = catalog.cachedVideos(in: category, contentType: contentType) {
            applySourceVideos(cachedVideos)
            await refreshBrowseResultsNow()
            phase = .done
            return
        }

        await loadSelectedCategory(policy: .cachedThenRefresh)
    }

    func video(for item: MoviesBrowseItem) -> Video? {
        videosByID[item.id]
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

    private func loadSelectedCategory(policy: CatalogLoadPolicy = .cachedThenRefresh) async {
        guard let category = selectedCategory else {
            sourceItems = []
            videosByID = [:]
            browseResults = []
            phase = .done
            return
        }

        if policy != .refreshNow,
           let cachedVideos = catalog.cachedVideos(in: category, contentType: contentType) {
            applySourceVideos(cachedVideos)
            await refreshBrowseResultsNow()
            phase = .done
        }

        if policy == .refreshNow || browseResults.isEmpty {
            phase = .fetching
            if policy == .refreshNow {
                browseResults = []
            }
        }

        do {
            try await catalog.getStreams(in: category, contentType: contentType, policy: policy)
            let resolvedVideos = catalog.cachedVideos(in: category, contentType: contentType) ?? []
            applySourceVideos(resolvedVideos)
            await refreshBrowseResultsNow()
            phase = .done
        } catch {
            phase = .error(error)
        }
    }

    private func applySourceVideos(_ videos: [Video]) {
        videosByID = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, $0) })
        sourceItems = videos.map(Self.makeSourceItem)
    }

    private func scheduleBrowseResultsRefresh() {
        browseResultsTask?.cancel()
        let revision = UUID()
        browseResultsRevision = revision
        let queryText = queryText
        let browseSort = browseSort
        let sourceItems = sourceItems

        if sourceItems.count <= DerivationPolicy.synchronousThreshold {
            browseResults = Self.deriveBrowseResults(
                from: sourceItems,
                queryText: queryText,
                browseSort: browseSort
            )
            return
        }

        browseResultsTask = Task { [weak self] in
            guard let self else { return }
            let results = await Self.deriveBrowseResultsAsync(
                from: sourceItems,
                queryText: queryText,
                browseSort: browseSort
            )
            guard !Task.isCancelled, self.browseResultsRevision == revision else { return }
            self.browseResults = results
        }
    }

    private func refreshBrowseResultsNow() async {
        browseResultsTask?.cancel()
        let revision = UUID()
        browseResultsRevision = revision
        let results = await Self.deriveBrowseResultsAsync(
            from: sourceItems,
            queryText: queryText,
            browseSort: browseSort
        )
        guard browseResultsRevision == revision else { return }
        browseResults = results
    }

    nonisolated private static func deriveBrowseResultsAsync(
        from sourceItems: [MoviesBrowseSourceItem],
        queryText: String,
        browseSort: BrowseSort
    ) async -> [MoviesBrowseItem] {
        await Task.detached(priority: .userInitiated) {
            deriveBrowseResults(
                from: sourceItems,
                queryText: queryText,
                browseSort: browseSort
            )
        }.value
    }

    nonisolated private static func deriveBrowseResults(
        from sourceItems: [MoviesBrowseSourceItem],
        queryText: String,
        browseSort: BrowseSort
    ) -> [MoviesBrowseItem] {
        let trimmedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = trimmedQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        let filteredItems: [MoviesBrowseSourceItem]
        if normalizedQuery.isEmpty {
            filteredItems = sourceItems
        } else {
            filteredItems = sourceItems.filter { $0.normalizedTitle.localizedCaseInsensitiveContains(normalizedQuery) }
        }

        let sortedItems: [MoviesBrowseSourceItem]
        switch browseSort {
        case .title:
            sortedItems = filteredItems.sorted { lhs, rhs in
                let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }
                return lhs.id < rhs.id
            }
        case .newest:
            sortedItems = filteredItems.sorted { lhs, rhs in
                if lhs.addedAtReferenceDate != rhs.addedAtReferenceDate {
                    return lhs.addedAtReferenceDate > rhs.addedAtReferenceDate
                }
                if lhs.ratingValue != rhs.ratingValue {
                    return lhs.ratingValue > rhs.ratingValue
                }
                let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }
                return lhs.id < rhs.id
            }
        case .rating:
            sortedItems = filteredItems.sorted { lhs, rhs in
                if lhs.ratingValue != rhs.ratingValue {
                    return lhs.ratingValue > rhs.ratingValue
                }
                if lhs.addedAtReferenceDate != rhs.addedAtReferenceDate {
                    return lhs.addedAtReferenceDate > rhs.addedAtReferenceDate
                }
                let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }
                return lhs.id < rhs.id
            }
        }

        return sortedItems.map {
            MoviesBrowseItem(
                id: $0.id,
                title: $0.title,
                artworkURL: $0.artworkURL,
                ratingText: $0.ratingText,
                languageText: $0.languageText,
            )
        }
    }

    private static func makeSourceItem(from video: Video) -> MoviesBrowseSourceItem {
        let languageText = LanguageTaggedText(video.name).languageCode
        let ratingText = video.rating.map {
            $0.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
        }
        let normalizedTitle = video.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        return MoviesBrowseSourceItem(
            id: video.id,
            title: video.name,
            normalizedTitle: normalizedTitle,
            artworkURL: video.coverImageURL.flatMap(URL.init(string:)),
            ratingText: ratingText,
            languageText: languageText,
            ratingValue: video.rating ?? .leastNormalMagnitude,
            addedAtReferenceDate: parseDate(video.addedAtRaw)?.timeIntervalSinceReferenceDate ?? .leastNormalMagnitude
        )
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
