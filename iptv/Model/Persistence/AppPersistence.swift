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
        Video.self,
        Category.self,
        VideoInfo.self,
        PersistedCategoryRecord.self,
        PersistedStreamRecord.self,
        PersistedCategoryRefreshStateRecord.self,
        PersistedMovieDetailRecord.self,
        PersistedSeriesDetailRecord.self,
        PersistedSearchDocumentRecord.self,
        PersistedSearchIndexedCategoryRecord.self,
        PersistedFavoriteStoreRecord.self,
        PersistedWatchActivityStoreRecord.self,
        PersistedDownloadGroupStoreRecord.self,
        PersistedDownloadAssetStoreRecord.self,
        PersistedOfflineMetadataStoreRecord.self
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
