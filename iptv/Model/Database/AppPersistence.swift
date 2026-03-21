//
//  AppPersistence.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import Foundation
import SwiftData

enum AppPersistence {
    static let schema = Schema([
        Provider.self,
        XtreamProvider.self,
        Category.self,
        MovieCategory.self,
        SeriesCategory.self,
        Movie.self,
        Series.self,
        Episode.self,
        Media.self,
        MediaInfo.self,
        MediaSource.self,
        Download.self,
        WatchActivity.self,
    ])

    static func makeModelContainer(
        isStoredInMemoryOnly: Bool = false
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
