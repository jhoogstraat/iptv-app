//
//  RecommendationProvider.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation

protocol RecommendationProviding {
    func build(context: RecommendationContext) async throws -> (hero: ForYouItem?, sections: [ForYouSection])
}

struct RemoteRecommendationProvider: RecommendationProviding {
    func build(context: RecommendationContext) async throws -> (hero: ForYouItem?, sections: [ForYouSection]) {
        (nil, [])
    }
}

struct LocalRecommendationProvider: RecommendationProviding {
    private let ranker: LocalRecommendationRanker

    init(ranker: LocalRecommendationRanker = LocalRecommendationRanker()) {
        self.ranker = ranker
    }

    func build(context: RecommendationContext) async throws -> (hero: ForYouItem?, sections: [ForYouSection]) {
        let index = ranker.buildCatalogIndex(from: context)

        let continueWatching = ranker.continueWatching(records: context.watchRecords)
        let becauseYouWatched = ranker.becauseYouWatched(context: context, index: index)
        let trending = ranker.trending(index: index)
        let criticallyAcclaimed = ranker.criticallyAcclaimed(index: index)
        let newAdditions = ranker.newAdditions(index: index)
        let bingeWorthySeries = ranker.bingeWorthySeries(index: index)

        let hero = ranker.chooseHero(
            becauseYouWatched: becauseYouWatched,
            criticallyAcclaimed: criticallyAcclaimed,
            trending: trending,
            continueWatching: continueWatching
        )

        var seenIDs = Set<String>()
        if let hero {
            seenIDs.insert(hero.id)
        }

        let continueWatchingUnique = ranker.deduplicated(continueWatching, excluding: &seenIDs)
        let becauseUnique = ranker.deduplicated(becauseYouWatched, excluding: &seenIDs)
        let trendingUnique = ranker.deduplicated(trending, excluding: &seenIDs)
        let acclaimedUnique = ranker.deduplicated(criticallyAcclaimed, excluding: &seenIDs)
        let additionsUnique = ranker.deduplicated(newAdditions, excluding: &seenIDs)
        let bingeUnique = ranker.deduplicated(bingeWorthySeries, excluding: &seenIDs)

        var sections: [ForYouSection] = []

        if !continueWatchingUnique.isEmpty {
            sections.append(
                ForYouSection(
                    id: "continue-watching",
                    title: "Continue Watching",
                    subtitle: nil,
                    style: .continueWatchingRail,
                    items: continueWatchingUnique
                )
            )
        }

        if becauseUnique.count >= 8 {
            sections.append(
                ForYouSection(
                    id: "because-you-watched",
                    title: "Because You Watched",
                    subtitle: nil,
                    style: .posterRail,
                    items: becauseUnique
                )
            )
        }

        if trendingUnique.count >= 8 {
            sections.append(
                ForYouSection(
                    id: "trending",
                    title: "Trending on Your Provider",
                    subtitle: nil,
                    style: .posterRail,
                    items: trendingUnique
                )
            )
        }

        if acclaimedUnique.count >= 8 {
            sections.append(
                ForYouSection(
                    id: "critically-acclaimed",
                    title: "Critically Acclaimed",
                    subtitle: nil,
                    style: .posterRail,
                    items: acclaimedUnique
                )
            )
        }

        if additionsUnique.count >= 8 {
            sections.append(
                ForYouSection(
                    id: "new-additions",
                    title: "New Additions",
                    subtitle: nil,
                    style: .posterRail,
                    items: additionsUnique
                )
            )
        }

        if bingeUnique.count >= 8 {
            sections.append(
                ForYouSection(
                    id: "binge-worthy-series",
                    title: "Binge-Worthy Series",
                    subtitle: nil,
                    style: .posterRail,
                    items: bingeUnique
                )
            )
        }

        return (hero, sections)
    }
}
