import Foundation
import SQLiteData
import Testing

@testable import iptv

@MainActor
@Suite("Favorites", .serialized)
struct FavoriteStoreTests {
    @Test func favoritesAreIsolatedWhenActiveProfileChanges() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let defaults = UserDefaults.standard
            let originalProfileID = UserProfileStore.activeProfileID(defaults: defaults)
            defer { UserProfileStore.setActive(originalProfileID, defaults: defaults) }

            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            let media = try insertMedia(sourceID: 700, title: "Profile Favorite", categoryID: nil, database: database)
            UserProfileStore.setActive(UserProfileStore.primaryProfileID, defaults: defaults)
            _ = try FavoriteStore.add(media, providerID: providerID, database: database, defaults: defaults)

            let second = try UserProfileStore.create(name: "Guest", database: database, defaults: defaults)
            #expect(UserProfileStore.activeProfileID(defaults: defaults) == second.id)
            #expect(FavoriteStore.isFavorite(media, providerID: providerID, database: database) == false)

            UserProfileStore.setActive(UserProfileStore.primaryProfileID, defaults: defaults)
            #expect(FavoriteStore.isFavorite(media, providerID: providerID, database: database))
        }
    }

    @Test func addToggleAndListFavoritesAreProviderScopedAndJoinedToLocalMedia() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let primaryProviderID = try insertProvider(name: "Primary", isActive: true, database: database)
            let secondaryProviderID = try insertProvider(name: "Secondary", isActive: false, database: database)
            let categoryID = try insertCategory(title: "|US| Movies", database: database)
            let media = try insertMedia(sourceID: 701, title: "Favorite Me", categoryID: categoryID, database: database)

            #expect(
                try FavoriteStore.add(media, providerID: primaryProviderID, database: database)
                    == .added
            )
            #expect(
                try FavoriteStore.add(
                    media,
                    providerID: secondaryProviderID,
                    categoryTitle: "Other",
                    database: database
                ) == .added
            )

            #expect(FavoriteStore.isFavorite(media, providerID: primaryProviderID, database: database))
            #expect(FavoriteStore.isFavorite(media, providerID: secondaryProviderID, database: database))

            let primaryFavorite = try #require(
                FavoriteStore.favorite(for: media, providerID: primaryProviderID, database: database)
            )
            #expect(primaryFavorite.title == "Favorite Me")
            #expect(primaryFavorite.artworkURL == media.coverURL)
            #expect(primaryFavorite.categoryID == categoryID)
            #expect(primaryFavorite.categoryTitle == "|US| Movies")

            let primaryItems = FavoriteStore.favorites(for: primaryProviderID, database: database)
            #expect(primaryItems.count == 1)
            #expect(primaryItems.first?.media?.id == media.id)
            #expect(primaryItems.first?.isAvailableLocally == true)

            let removed = try FavoriteStore.toggle(
                media,
                providerID: primaryProviderID,
                database: database
            )
            #expect(removed == .removed)
            #expect(removed.isFavorite == false)
            #expect(FavoriteStore.isFavorite(media, providerID: primaryProviderID, database: database) == false)
            #expect(FavoriteStore.isFavorite(media, providerID: secondaryProviderID, database: database))
        }
    }

    @Test func failedAddAndDeleteThrowWithoutBumpingRevision() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            let media = try insertMedia(sourceID: 702, title: "Failure Probe", categoryID: nil, database: database)
            let suiteName = "favorite-failure-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(41, forKey: FavoriteStore.revisionKey)

            try database.write { db in
                try #sql("""
                CREATE TRIGGER "fail_favorite_insert"
                BEFORE INSERT ON "favorites"
                BEGIN
                    SELECT RAISE(ABORT, 'forced favorite insert failure');
                END
                """).execute(db)
            }

            do {
                _ = try FavoriteStore.add(
                    media,
                    providerID: providerID,
                    database: database,
                    defaults: defaults
                )
                Issue.record("Expected favorite insertion to throw.")
            } catch {
                #expect(error.localizedDescription.contains("forced favorite insert failure"))
            }

            #expect(defaults.integer(forKey: FavoriteStore.revisionKey) == 41)
            #expect(FavoriteStore.isFavorite(media, providerID: providerID, database: database) == false)

            try database.write { db in
                try #sql("""
                DROP TRIGGER "fail_favorite_insert"
                """).execute(db)
            }
            #expect(
                try FavoriteStore.add(
                    media,
                    providerID: providerID,
                    database: database,
                    defaults: defaults
                ) == .added
            )
            #expect(defaults.integer(forKey: FavoriteStore.revisionKey) == 42)

            try database.write { db in
                try #sql("""
                CREATE TRIGGER "fail_favorite_delete"
                BEFORE DELETE ON "favorites"
                BEGIN
                    SELECT RAISE(ABORT, 'forced favorite delete failure');
                END
                """).execute(db)
            }

            do {
                _ = try FavoriteStore.remove(
                    media,
                    providerID: providerID,
                    database: database,
                    defaults: defaults
                )
                Issue.record("Expected favorite deletion to throw.")
            } catch {
                #expect(error.localizedDescription.contains("forced favorite delete failure"))
            }

            #expect(defaults.integer(forKey: FavoriteStore.revisionKey) == 42)
            #expect(FavoriteStore.isFavorite(media, providerID: providerID, database: database))

            try database.write { db in
                try #sql("""
                DROP TRIGGER "fail_favorite_delete"
                """).execute(db)
            }
        }
    }

    @Test func joinedFavoriteUsesCurrentCategoryAndFallsBackToInsertionSnapshotWhenUnavailable() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            let originalCategoryID = try insertCategory(title: "Original Movies", database: database)
            let currentCategoryID = try insertCategory(title: "Current Movies", database: database)
            let media = try insertMedia(
                sourceID: 703,
                title: "Remapped Favorite",
                categoryID: originalCategoryID,
                database: database
            )

            _ = try FavoriteStore.add(media, providerID: providerID, database: database)
            try database.write { db in
                try Media.find(media.id).update {
                    $0.categoryID = #bind(currentCategoryID)
                }.execute(db)
            }

            let remappedItem = try #require(
                FavoriteStore.favorites(for: providerID, database: database).first
            )
            #expect(remappedItem.categoryTitle == "Current Movies")
            #expect(remappedItem.media?.categoryID == currentCategoryID)

            try database.write { db in
                try Media.find(media.id).delete().execute(db)
                try Category.find(currentCategoryID).delete().execute(db)
                try Category.find(originalCategoryID).delete().execute(db)
            }

            let unavailableItem = try #require(
                FavoriteStore.favorites(for: providerID, database: database).first
            )
            #expect(unavailableItem.media == nil)
            #expect(unavailableItem.category == nil)
            #expect(unavailableItem.categoryTitle == "Original Movies")
        }
    }

    @Test func explicitProviderDeleteClearsFavorites() throws {
        try withTestDatabase { database in
            try resetDatabase(database)
            let providerID = try insertProvider(name: "Primary", isActive: true, database: database)
            let media = try insertMedia(sourceID: 88, title: "Tracked", categoryID: nil, database: database)
            _ = try FavoriteStore.add(media, providerID: providerID, database: database)
            #expect(FavoriteStore.isFavorite(media, providerID: providerID, database: database))

            let credentialStore = TestProviderCredentialStore(passwords: ["test-Primary": "pass"])
            let manager = ProviderManager(database: database, credentialStore: credentialStore)
            try manager.loadActive()
            try manager.delete(provider: providerID)

            #expect(FavoriteStore.isFavorite(media, providerID: providerID, database: database) == false)
        }
    }

    private func withTestDatabase<T>(_ operation: (any DatabaseWriter) throws -> T) throws -> T {
        let database = try testAppDatabase(credentialStore: TestProviderCredentialStore())
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
                    credentialReference: "test-\(name)",
                    endpoint: endpoint,
                    allowsInsecureHTTP: false,
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
