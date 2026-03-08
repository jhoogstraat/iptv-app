//
//  LocalRecommendationRanker.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation

struct LocalRecommendationRanker {
    private let now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    func buildCatalogIndex(from context: RecommendationContext) -> CatalogIndex {
        var videosByKey: [String: Video] = [:]
        var categoryNamesByKey: [String: Set<String>] = [:]
        var categoryDensity: [String: Int] = [:]

        for (category, videos) in context.vodCatalog {
            for video in videos {
                let key = makeVideoKey(video)
                videosByKey[key] = videosByKey[key] ?? video
                categoryNamesByKey[key, default: []].insert(normalizeCategory(category.name))
                categoryDensity[normalizeCategory(category.name), default: 0] += 1
            }
        }

        for (category, videos) in context.seriesCatalog {
            for video in videos {
                let key = makeVideoKey(video)
                videosByKey[key] = videosByKey[key] ?? video
                categoryNamesByKey[key, default: []].insert(normalizeCategory(category.name))
                categoryDensity[normalizeCategory(category.name), default: 0] += 1
            }
        }

        return CatalogIndex(
            videosByKey: videosByKey,
            categoryNamesByKey: categoryNamesByKey,
            categoryDensity: categoryDensity
        )
    }

    func continueWatching(
        records: [WatchActivityRecord],
        maxItems: Int = 20
    ) -> [ForYouItem] {
        records
            .filter { !$0.isCompleted }
            .filter { $0.progressFraction >= 0.05 && $0.progressFraction <= 0.95 }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            .prefix(maxItems)
            .map { record in
                ForYouItem.from(video: record.asVideo(), progress: record.progress)
            }
    }

    func becauseYouWatched(
        context: RecommendationContext,
        index: CatalogIndex,
        maxItems: Int = 24
    ) -> [ForYouItem] {
        guard !context.watchRecords.isEmpty else { return [] }

        let watchedKeys = Set(context.watchRecords.map { makeVideoKey(contentType: $0.contentType, id: $0.videoID) })
        let watchedCategoryWeights = weightedCategories(from: context.watchRecords, index: index)
        let watchedLanguages = weightedLanguages(from: context.watchRecords)

        let scored = index.videosByKey.values
            .filter { !watchedKeys.contains(makeVideoKey($0)) }
            .map { video -> (video: Video, score: Double) in
                let key = makeVideoKey(video)
                let categories = index.categoryNamesByKey[key] ?? []

                var overlapScore: Double = 0
                for category in categories {
                    overlapScore += watchedCategoryWeights[category] ?? 0
                }
                overlapScore = min(overlapScore, 1)

                let languageScore: Double
                if let language = video.language?.lowercased() {
                    languageScore = min(watchedLanguages[language] ?? 0, 1)
                } else {
                    languageScore = 0
                }

                let ratingScore = normalizedRating(video.rating)
                let recencyScore = normalizedRecency(video)

                let score = overlapScore * 0.5 + languageScore * 0.2 + ratingScore * 0.2 + recencyScore * 0.1
                return (video, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.video.name != rhs.video.name { return lhs.video.name < rhs.video.name }
                return lhs.video.id < rhs.video.id
            }

        return Array(scored.prefix(maxItems)).map { ForYouItem.from(video: $0.video) }
    }

    func trending(
        index: CatalogIndex,
        maxItems: Int = 24
    ) -> [ForYouItem] {
        let maxDensity = max(index.categoryDensity.values.max() ?? 1, 1)

        let scored = index.videosByKey.values
            .map { video -> (video: Video, score: Double) in
                let key = makeVideoKey(video)
                let categories = index.categoryNamesByKey[key] ?? []
                let density = categories.map { Double(index.categoryDensity[$0] ?? 0) / Double(maxDensity) }.max() ?? 0

                let score = normalizedRating(video.rating) * 0.5 + normalizedRecency(video) * 0.3 + density * 0.2
                return (video, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.video.name != rhs.video.name { return lhs.video.name < rhs.video.name }
                return lhs.video.id < rhs.video.id
            }

        return Array(scored.prefix(maxItems)).map { ForYouItem.from(video: $0.video) }
    }

    func criticallyAcclaimed(index: CatalogIndex, minRating: Double = 7.5, maxItems: Int = 24) -> [ForYouItem] {
        index.videosByKey.values
            .filter { ($0.rating ?? 0) >= minRating }
            .sorted { lhs, rhs in
                if lhs.rating != rhs.rating { return (lhs.rating ?? 0) > (rhs.rating ?? 0) }
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id < rhs.id
            }
            .prefix(maxItems)
            .map { ForYouItem.from(video: $0) }
    }

    func newAdditions(index: CatalogIndex, maxItems: Int = 24) -> [ForYouItem] {
        index.videosByKey.values
            .compactMap { video -> (video: Video, date: Date)? in
                guard let date = parseAddedDate(video.addedAtRaw) else { return nil }
                return (video, date)
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                if lhs.video.name != rhs.video.name { return lhs.video.name < rhs.video.name }
                return lhs.video.id < rhs.video.id
            }
            .prefix(maxItems)
            .map { ForYouItem.from(video: $0.video, forceBadge: .isNew) }
    }

    func bingeWorthySeries(index: CatalogIndex, maxItems: Int = 24) -> [ForYouItem] {
        var perCategoryCount: [String: Int] = [:]

        let sortedSeries = index.videosByKey.values
            .filter { $0.xtreamContentType == .series }
            .filter { ($0.rating ?? 0) >= 7.0 }
            .sorted { lhs, rhs in
                if lhs.rating != rhs.rating { return (lhs.rating ?? 0) > (rhs.rating ?? 0) }
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id < rhs.id
            }

        var output: [ForYouItem] = []
        output.reserveCapacity(maxItems)

        for video in sortedSeries {
            guard output.count < maxItems else { break }
            let key = makeVideoKey(video)
            let categories = Array(index.categoryNamesByKey[key] ?? ["uncategorized"])

            let selectedCategory = categories.min { lhs, rhs in
                let left = perCategoryCount[lhs] ?? 0
                let right = perCategoryCount[rhs] ?? 0
                if left != right { return left < right }
                return lhs < rhs
            } ?? "uncategorized"

            guard (perCategoryCount[selectedCategory] ?? 0) < 4 else { continue }
            perCategoryCount[selectedCategory, default: 0] += 1
            output.append(ForYouItem.from(video: video, forceBadge: .series))
        }

        return output
    }

    func chooseHero(
        becauseYouWatched: [ForYouItem],
        criticallyAcclaimed: [ForYouItem],
        trending: [ForYouItem],
        continueWatching: [ForYouItem]
    ) -> ForYouItem? {
        continueWatching.first ?? becauseYouWatched.first ?? criticallyAcclaimed.first ?? trending.first
    }

    func deduplicated(_ items: [ForYouItem], excluding seen: inout Set<String>) -> [ForYouItem] {
        var result: [ForYouItem] = []
        result.reserveCapacity(items.count)

        for item in items {
            if seen.insert(item.id).inserted {
                result.append(item)
            }
        }
        return result
    }

    func normalizedRecency(_ video: Video) -> Double {
        guard let date = parseAddedDate(video.addedAtRaw) else { return 0 }
        let ageDays = max(now.timeIntervalSince(date) / 86_400, 0)
        if ageDays >= 120 { return 0 }
        return max(1 - (ageDays / 120), 0)
    }

    func parseAddedDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }

        if let timestamp = Double(raw), timestamp > 0 {
            if timestamp > 10_000_000_000 {
                return Date(timeIntervalSince1970: timestamp / 1000)
            }
            return Date(timeIntervalSince1970: timestamp)
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "yyyyMMdd",
            "dd-MM-yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in formats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: trimmed) {
                return parsed
            }
        }

        return nil
    }

    private func normalizedRating(_ value: Double?) -> Double {
        guard let value else { return 0 }
        return min(max(value / 10, 0), 1)
    }

    private func weightedCategories(from records: [WatchActivityRecord], index: CatalogIndex) -> [String: Double] {
        var values: [String: Double] = [:]
        for record in records.prefix(30) {
            let key = makeVideoKey(contentType: record.contentType, id: record.videoID)
            let categories = index.categoryNamesByKey[key] ?? []
            let weight = max(1 - (record.progressFraction * 0.4), 0.6)
            for category in categories {
                values[category, default: 0] += weight
            }
        }

        let maxWeight = max(values.values.max() ?? 1, 1)
        return values.mapValues { min($0 / maxWeight, 1) }
    }

    private func weightedLanguages(from records: [WatchActivityRecord]) -> [String: Double] {
        var values: [String: Double] = [:]
        for record in records.prefix(30) {
            guard let language = language(from: record.title) else { continue }
            values[language, default: 0] += 1
        }

        let maxWeight = max(values.values.max() ?? 1, 1)
        return values.mapValues { min($0 / maxWeight, 1) }
    }

    private func language(from title: String) -> String? {
        LanguageTaggedText(title).languageCode?.lowercased()
    }

    private func makeVideoKey(_ video: Video) -> String {
        makeVideoKey(contentType: video.contentType, id: video.id)
    }

    private func makeVideoKey(contentType: String, id: Int) -> String {
        "\(contentType):\(id)"
    }

    private func normalizeCategory(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct CatalogIndex {
    let videosByKey: [String: Video]
    let categoryNamesByKey: [String: Set<String>]
    let categoryDensity: [String: Int]
}
