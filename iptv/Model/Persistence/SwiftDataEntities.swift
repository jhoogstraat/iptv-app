//
//  SwiftDataEntities.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import Foundation
import SwiftData

@Model
final class PersistedCategoryRecord {
    @Attribute(.unique) var id: String
    var providerFingerprint: String
    var contentType: String
    var categoryID: String
    var name: String
    var sortIndex: Int
    var updatedAt: Date

    init(
        id: String,
        providerFingerprint: String,
        contentType: String,
        categoryID: String,
        name: String,
        sortIndex: Int,
        updatedAt: Date
    ) {
        self.id = id
        self.providerFingerprint = providerFingerprint
        self.contentType = contentType
        self.categoryID = categoryID
        self.name = name
        self.sortIndex = sortIndex
        self.updatedAt = updatedAt
    }
}

@Model
final class PersistedStreamRecord {
    @Attribute(.unique) var id: String
    var providerFingerprint: String
    var contentType: String
    var categoryID: String
    var pageToken: String?
    var videoID: Int
    var sortIndex: Int
    var name: String
    var containerExtension: String
    var playbackContentType: String
    var coverImageURL: String?
    var tmdbId: String?
    var rating: Double?
    var addedAtRaw: String?
    var savedAt: Date
    var lastAccessAt: Date

    init(
        id: String,
        providerFingerprint: String,
        contentType: String,
        categoryID: String,
        pageToken: String?,
        videoID: Int,
        sortIndex: Int,
        name: String,
        containerExtension: String,
        playbackContentType: String,
        coverImageURL: String?,
        tmdbId: String?,
        rating: Double?,
        addedAtRaw: String?,
        savedAt: Date,
        lastAccessAt: Date
    ) {
        self.id = id
        self.providerFingerprint = providerFingerprint
        self.contentType = contentType
        self.categoryID = categoryID
        self.pageToken = pageToken
        self.videoID = videoID
        self.sortIndex = sortIndex
        self.name = name
        self.containerExtension = containerExtension
        self.playbackContentType = playbackContentType
        self.coverImageURL = coverImageURL
        self.tmdbId = tmdbId
        self.rating = rating
        self.addedAtRaw = addedAtRaw
        self.savedAt = savedAt
        self.lastAccessAt = lastAccessAt
    }
}

@Model
final class PersistedMovieDetailRecord {
    @Attribute(.unique) var id: String
    var providerFingerprint: String
    var videoID: Int
    var imageURLs: [String]
    var plot: String
    var cast: String
    var director: String
    var genre: String
    var releaseDate: String
    var durationLabel: String
    var runtimeMinutes: Int?
    var ageRating: String
    var country: String
    var rating: Double?
    var streamBitrate: Int?
    var audioDescription: String
    var videoResolution: String
    var videoFrameRate: Double?
    var savedAt: Date
    var lastAccessAt: Date

    init(
        id: String,
        providerFingerprint: String,
        videoID: Int,
        imageURLs: [String],
        plot: String,
        cast: String,
        director: String,
        genre: String,
        releaseDate: String,
        durationLabel: String,
        runtimeMinutes: Int?,
        ageRating: String,
        country: String,
        rating: Double?,
        streamBitrate: Int?,
        audioDescription: String,
        videoResolution: String,
        videoFrameRate: Double?,
        savedAt: Date,
        lastAccessAt: Date
    ) {
        self.id = id
        self.providerFingerprint = providerFingerprint
        self.videoID = videoID
        self.imageURLs = imageURLs
        self.plot = plot
        self.cast = cast
        self.director = director
        self.genre = genre
        self.releaseDate = releaseDate
        self.durationLabel = durationLabel
        self.runtimeMinutes = runtimeMinutes
        self.ageRating = ageRating
        self.country = country
        self.rating = rating
        self.streamBitrate = streamBitrate
        self.audioDescription = audioDescription
        self.videoResolution = videoResolution
        self.videoFrameRate = videoFrameRate
        self.savedAt = savedAt
        self.lastAccessAt = lastAccessAt
    }
}

@Model
final class PersistedSeriesDetailRecord {
    @Attribute(.unique) var id: String
    var providerFingerprint: String
    var seriesID: Int
    var payload: Data
    var savedAt: Date
    var lastAccessAt: Date

    init(
        id: String,
        providerFingerprint: String,
        seriesID: Int,
        payload: Data,
        savedAt: Date,
        lastAccessAt: Date
    ) {
        self.id = id
        self.providerFingerprint = providerFingerprint
        self.seriesID = seriesID
        self.payload = payload
        self.savedAt = savedAt
        self.lastAccessAt = lastAccessAt
    }
}

@Model
final class PersistedSearchDocumentRecord {
    @Attribute(.unique) var id: String
    var providerFingerprint: String
    var videoID: Int
    var indexedContentType: String
    var playbackContentType: String
    var title: String
    var normalizedTitle: String
    var containerExtension: String
    var coverImageURL: String?
    var rating: Double?
    var addedAtRaw: String?
    var addedAt: Date?
    var language: String?
    var normalizedLanguage: String?
    var categoryIDs: [String]
    var categories: [String]
    var normalizedCategories: [String]
    var genres: [String]
    var normalizedGenres: [String]

    init(
        id: String,
        providerFingerprint: String,
        videoID: Int,
        indexedContentType: String,
        playbackContentType: String,
        title: String,
        normalizedTitle: String,
        containerExtension: String,
        coverImageURL: String?,
        rating: Double?,
        addedAtRaw: String?,
        addedAt: Date?,
        language: String?,
        normalizedLanguage: String?,
        categoryIDs: [String],
        categories: [String],
        normalizedCategories: [String],
        genres: [String],
        normalizedGenres: [String]
    ) {
        self.id = id
        self.providerFingerprint = providerFingerprint
        self.videoID = videoID
        self.indexedContentType = indexedContentType
        self.playbackContentType = playbackContentType
        self.title = title
        self.normalizedTitle = normalizedTitle
        self.containerExtension = containerExtension
        self.coverImageURL = coverImageURL
        self.rating = rating
        self.addedAtRaw = addedAtRaw
        self.addedAt = addedAt
        self.language = language
        self.normalizedLanguage = normalizedLanguage
        self.categoryIDs = categoryIDs
        self.categories = categories
        self.normalizedCategories = normalizedCategories
        self.genres = genres
        self.normalizedGenres = normalizedGenres
    }
}

@Model
final class PersistedSearchIndexedCategoryRecord {
    @Attribute(.unique) var id: String
    var providerFingerprint: String
    var contentType: String
    var categoryID: String

    init(id: String, providerFingerprint: String, contentType: String, categoryID: String) {
        self.id = id
        self.providerFingerprint = providerFingerprint
        self.contentType = contentType
        self.categoryID = categoryID
    }
}

@Model
final class PersistedFavoriteStoreRecord {
    @Attribute(.unique) var id: String
    var providerFingerprint: String
    var videoID: Int
    var contentType: String
    var title: String
    var coverImageURL: String?
    var containerExtension: String
    var rating: Double?
    var createdAt: Date

    init(
        id: String,
        providerFingerprint: String,
        videoID: Int,
        contentType: String,
        title: String,
        coverImageURL: String?,
        containerExtension: String,
        rating: Double?,
        createdAt: Date
    ) {
        self.id = id
        self.providerFingerprint = providerFingerprint
        self.videoID = videoID
        self.contentType = contentType
        self.title = title
        self.coverImageURL = coverImageURL
        self.containerExtension = containerExtension
        self.rating = rating
        self.createdAt = createdAt
    }
}

@Model
final class PersistedWatchActivityStoreRecord {
    @Attribute(.unique) var id: String
    var providerFingerprint: String
    var videoID: Int
    var contentType: String
    var title: String
    var coverImageURL: String?
    var containerExtension: String
    var rating: Double?
    var lastPositionSeconds: Double
    var durationSeconds: Double?
    var progressFraction: Double
    var lastPlayedAt: Date
    var isCompleted: Bool

    init(
        id: String,
        providerFingerprint: String,
        videoID: Int,
        contentType: String,
        title: String,
        coverImageURL: String?,
        containerExtension: String,
        rating: Double?,
        lastPositionSeconds: Double,
        durationSeconds: Double?,
        progressFraction: Double,
        lastPlayedAt: Date,
        isCompleted: Bool
    ) {
        self.id = id
        self.providerFingerprint = providerFingerprint
        self.videoID = videoID
        self.contentType = contentType
        self.title = title
        self.coverImageURL = coverImageURL
        self.containerExtension = containerExtension
        self.rating = rating
        self.lastPositionSeconds = lastPositionSeconds
        self.durationSeconds = durationSeconds
        self.progressFraction = progressFraction
        self.lastPlayedAt = lastPlayedAt
        self.isCompleted = isCompleted
    }
}

@Model
final class PersistedDownloadGroupStoreRecord {
    @Attribute(.unique) var id: String
    var scopeProfileID: String
    var scopeProviderFingerprint: String
    var kind: String
    var title: String
    var parentVideoID: Int
    var contentType: String
    var coverImageURL: String?
    var childAssetIDs: [String]
    var status: String
    var completedAssetCount: Int
    var totalAssetCount: Int
    var bytesWritten: Int64
    var expectedBytes: Int64?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        scopeProfileID: String,
        scopeProviderFingerprint: String,
        kind: String,
        title: String,
        parentVideoID: Int,
        contentType: String,
        coverImageURL: String?,
        childAssetIDs: [String],
        status: String,
        completedAssetCount: Int,
        totalAssetCount: Int,
        bytesWritten: Int64,
        expectedBytes: Int64?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.scopeProfileID = scopeProfileID
        self.scopeProviderFingerprint = scopeProviderFingerprint
        self.kind = kind
        self.title = title
        self.parentVideoID = parentVideoID
        self.contentType = contentType
        self.coverImageURL = coverImageURL
        self.childAssetIDs = childAssetIDs
        self.status = status
        self.completedAssetCount = completedAssetCount
        self.totalAssetCount = totalAssetCount
        self.bytesWritten = bytesWritten
        self.expectedBytes = expectedBytes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PersistedDownloadAssetStoreRecord {
    @Attribute(.unique) var id: String
    var scopeProfileID: String
    var scopeProviderFingerprint: String
    var videoID: Int
    var contentType: String
    var title: String
    var coverImageURL: String?
    var containerExtension: String
    var seriesID: Int?
    var seasonNumber: Int?
    var remoteURL: String
    var localURL: String?
    var resumeDataURL: String?
    var status: String
    var bytesWritten: Int64
    var expectedBytes: Int64?
    var attemptCount: Int
    var lastError: String?
    var metadataSnapshotID: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        scopeProfileID: String,
        scopeProviderFingerprint: String,
        videoID: Int,
        contentType: String,
        title: String,
        coverImageURL: String?,
        containerExtension: String,
        seriesID: Int?,
        seasonNumber: Int?,
        remoteURL: String,
        localURL: String?,
        resumeDataURL: String?,
        status: String,
        bytesWritten: Int64,
        expectedBytes: Int64?,
        attemptCount: Int,
        lastError: String?,
        metadataSnapshotID: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.scopeProfileID = scopeProfileID
        self.scopeProviderFingerprint = scopeProviderFingerprint
        self.videoID = videoID
        self.contentType = contentType
        self.title = title
        self.coverImageURL = coverImageURL
        self.containerExtension = containerExtension
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.remoteURL = remoteURL
        self.localURL = localURL
        self.resumeDataURL = resumeDataURL
        self.status = status
        self.bytesWritten = bytesWritten
        self.expectedBytes = expectedBytes
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.metadataSnapshotID = metadataSnapshotID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PersistedOfflineMetadataStoreRecord {
    @Attribute(.unique) var id: String
    var scopeProfileID: String
    var scopeProviderFingerprint: String
    var kind: String
    var videoID: Int
    var contentType: String
    var title: String
    var coverImageURL: String?
    var artworkPayload: Data
    var movieInfoPayload: Data?
    var seriesInfoPayload: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        scopeProfileID: String,
        scopeProviderFingerprint: String,
        kind: String,
        videoID: Int,
        contentType: String,
        title: String,
        coverImageURL: String?,
        artworkPayload: Data,
        movieInfoPayload: Data?,
        seriesInfoPayload: Data?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.scopeProfileID = scopeProfileID
        self.scopeProviderFingerprint = scopeProviderFingerprint
        self.kind = kind
        self.videoID = videoID
        self.contentType = contentType
        self.title = title
        self.coverImageURL = coverImageURL
        self.artworkPayload = artworkPayload
        self.movieInfoPayload = movieInfoPayload
        self.seriesInfoPayload = seriesInfoPayload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
