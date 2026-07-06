import Foundation
import SQLiteData
import Testing

@testable import iptv

@MainActor
@Suite("Favorites", .serialized)
struct FavoriteStoreTests {
    @Test func addToggleAndListFavoritesAreProviderScopedAndJoinedToLocalMedia() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let primaryProviderID = try insertProvider(name: "Primary", isActive: true, database: database)
            let secondaryProviderID = try insertProvider(name: "Secondary", isActive: false, database: database)
            let categoryID = try insertCategory(title: "|US| Movies", database: database)
            let media = try insertMedia(sourceID: 701, title: "Favorite Me", categoryID: categoryID, database: database)

            FavoriteStore.add(media, providerID: primaryProviderID, database: database)
            FavoriteStore.add(media, providerID: secondaryProviderID, categoryTitle: "Other", database: database)

            #expect(FavoriteStore.isFavorite(media, providerID: primaryProviderID, database: database))
            #expect(FavoriteStore.isFavorite(media, providerID: secondaryProviderID, database: database))

            let primaryFavorite = try #require(FavoriteStore.favorite(for: media, providerID: primaryProviderID, database: database))
            #expect(primaryFavorite.title == "Favorite Me")
            #expect(primaryFavorite.artworkURL == media.coverURL)
            #expect(primaryFavorite.categoryID == categoryID)
            #expect(primaryFavorite.categoryTitle == "|US| Movies")

            let primaryItems = FavoriteStore.favorites(for: primaryProviderID, database: database)
            #expect(primaryItems.count == 1)
            #expect(primaryItems.first?.media?.id == media.id)
            #expect(primaryItems.first?.isAvailableLocally == true)

            let removed = FavoriteStore.toggle(media, providerID: primaryProviderID, database: database)
            #expect(removed == false)
            #expect(FavoriteStore.isFavorite(media, providerID: primaryProviderID, database: database) == false)
            #expect(FavoriteStore.isFavorite(media, providerID: secondaryProviderID, database: database))
        }
    }

    @Test func providerEditAndDeleteClearFavoritesForActiveProvider() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            let media = try insertMedia(sourceID: 88, title: "Tracked", categoryID: nil, database: database)
            FavoriteStore.add(media, providerID: providerID, database: database)
            #expect(FavoriteStore.isFavorite(media, providerID: providerID, database: database))

            let manager = ProviderManager(database: database)
            try manager.loadActive()
            try manager.update(
                provider: Provider.Draft(
                    id: providerID,
                    kind: .xtream,
                    name: "Edited",
                    username: "user",
                    password: "pass",
                    endpoint: try #require(URL(string: "https://edited.example.com")),
                    isActive: true
                )
            )

            #expect(FavoriteStore.isFavorite(media, providerID: providerID, database: database) == false)

            FavoriteStore.add(media, providerID: providerID, database: database)
            try manager.delete(provider: providerID)

            #expect(FavoriteStore.isFavorite(media, providerID: providerID, database: database) == false)
        }
    }

    private func withTestDatabase<T>(_ operation: (any DatabaseWriter) throws -> T) throws -> T {
        let database = try appDatabase()
        return try operation(database)
    }

    private func resetDatabase(_ database: any DatabaseWriter) throws {
        try database.write { db in
            try Favorite.delete().execute(db)
            try WatchActivity.delete().execute(db)
            try SeriesSeason.delete().execute(db)
            try Media.delete().execute(db)
            try Category.delete().execute(db)
            try Provider.delete().execute(db)
        }
    }

    @discardableResult
    private func insertProvider(name: String, isActive: Bool, database: any DatabaseWriter) throws -> Provider.ID {
        let endpoint = try #require(URL(string: "https://example.com"))
        var providerID: Provider.ID?
        try database.write { db in
            let provider = try Provider.insert {
                Provider.Draft(
                    id: nil,
                    kind: .xtream,
                    name: name,
                    username: "user",
                    password: "pass",
                    endpoint: endpoint,
                    isActive: isActive
                )
            }
            .returning(\.self)
            .fetchOne(db)!
            providerID = provider.id
        }
        return try #require(providerID)
    }

    @discardableResult
    private func insertCategory(title: String, database: any DatabaseWriter) throws -> iptv.Category.ID {
        var categoryID: iptv.Category.ID?
        try database.write { db in
            let category = try iptv.Category.insert {
                iptv.Category.Draft(id: nil, sourceID: title, type: .movie, title: title, updatedAt: Date())
            }
            .returning(\.self)
            .fetchOne(db)!
            categoryID = category.id
        }
        return try #require(categoryID)
    }

    @discardableResult
    private func insertMedia(
        sourceID: Int,
        title: String,
        categoryID: iptv.Category.ID?,
        database: any DatabaseWriter
    ) throws -> Media {
        var media: Media?
        try database.write { db in
            media = try Media.insert {
                Media.Draft(
                    id: nil,
                    sourceID: sourceID,
                    type: .movie,
                    title: title,
                    categoryID: categoryID,
                    tmdbID: nil,
                    coverURL: URL(string: "https://img.example.com/poster.jpg"),
                    rating: 8.1,
                    parentSeriesID: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    containerExtension: "mp4",
                    synopsis: nil,
                    releaseDate: nil,
                    runtimeSeconds: 600,
                    genre: nil,
                    cast: nil,
                    director: nil,
                    trailer: nil,
                    addedAt: nil,
                    backdropURL: URL(string: "https://img.example.com/backdrop.jpg"),
                    country: nil,
                    updatedAt: Date(timeIntervalSince1970: 100)
                )
            }
            .returning(\.self)
            .fetchOne(db)!
        }
        return try #require(media)
    }
}
