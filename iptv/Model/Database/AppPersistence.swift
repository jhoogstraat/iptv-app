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
        Category.self,
        Movie.self,
        Series.self,
        Media.self,
        MovieMedia.self,
        EpisodeMedia.self,
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
