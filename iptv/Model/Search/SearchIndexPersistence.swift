//
//  SearchIndexPersistence.swift
//  iptv
//
//  Created by Codex on 15.03.26.
//

import Foundation
import SwiftData

@ModelActor
actor SearchIndexPersistence {
    func loadDocuments(
        providerFingerprint: String,
        acceptedContentTypes: Set<XtreamContentType>
    ) throws -> [SearchIndexStore.SearchDocument] {
        let rawAcceptedContentTypes = Set(acceptedContentTypes.map(\.rawValue))
        let records = try modelContext.fetch(
            FetchDescriptor<PersistedStreamRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )

        var documentsByKey: [String: SearchIndexStore.SearchDocument] = [:]
        documentsByKey.reserveCapacity(records.count)

        for record in records {
            guard let indexedContentType = XtreamContentType(rawValue: record.contentType),
                  rawAcceptedContentTypes.contains(indexedContentType.rawValue) else {
                continue
            }

            let key = Self.makeKey(contentType: indexedContentType, videoID: record.videoID)
            var categoryNamesByID = documentsByKey[key]?.categoryNamesByID ?? [:]
            var normalizedCategoryNamesByID = documentsByKey[key]?.normalizedCategoryNamesByID ?? [:]

            categoryNamesByID[record.categoryID] = record.categoryName
            normalizedCategoryNamesByID[record.categoryID] = record.normalizedCategoryName

            documentsByKey[key] = SearchIndexStore.SearchDocument(
                key: key,
                videoID: record.videoID,
                indexedContentType: indexedContentType,
                playbackContentType: record.playbackContentType,
                title: record.name,
                normalizedTitle: record.normalizedTitle,
                containerExtension: record.containerExtension,
                coverImageURL: record.coverImageURL,
                rating: record.rating,
                addedAtRaw: record.addedAtRaw,
                addedAt: record.addedAt,
                language: record.language,
                normalizedLanguage: record.normalizedLanguage,
                categoryNamesByID: categoryNamesByID,
                normalizedCategoryNamesByID: normalizedCategoryNamesByID
            )
        }

        return Array(documentsByKey.values)
    }

    func loadIndexedCategories(
        scope: SearchMediaScope,
        providerFingerprint: String
    ) throws -> Set<String> {
        let rawAcceptedContentTypes = Set(scope.acceptedContentTypes.map(\.rawValue))
        let records = try modelContext.fetch(
            FetchDescriptor<PersistedCategoryRefreshStateRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )

        return Set(
            records
                .filter { rawAcceptedContentTypes.contains($0.contentType) && $0.lastSuccessfulRefreshAt != nil }
                .map(\.categoryID)
        )
    }

    func replaceCategory(
        videos: [SearchVideoSnapshot],
        contentType: XtreamContentType,
        categoryID: String,
        categoryName: String,
        providerFingerprint: String
    ) throws {
        guard contentType == .vod || contentType == .series else { return }

        let rawContentType = contentType.rawValue
        let cleanedCategoryID = categoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCategoryName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategoryName = Self.normalize(cleanedCategoryName)
        let currentDate = Date()

        try modelContext.delete(
            model: PersistedStreamRecord.self,
            where: #Predicate {
                $0.providerFingerprint == providerFingerprint &&
                $0.contentType == rawContentType &&
                $0.categoryID == cleanedCategoryID
            }
        )

        for (index, video) in videos.enumerated() {
            let language = video.language?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? LanguageTaggedText(video.name).languageCode
            let addedAtRaw = video.addedAtRaw?.trimmingCharacters(in: .whitespacesAndNewlines)

            modelContext.insert(
                PersistedStreamRecord(
                    id: "\(providerFingerprint)|\(rawContentType)|\(cleanedCategoryID)|\(video.id)",
                    providerFingerprint: providerFingerprint,
                    contentType: rawContentType,
                    categoryID: cleanedCategoryID,
                    categoryName: cleanedCategoryName,
                    normalizedCategoryName: normalizedCategoryName,
                    pageToken: nil,
                    videoID: video.id,
                    sortIndex: index,
                    name: video.name,
                    normalizedTitle: Self.normalize(video.name),
                    language: language,
                    normalizedLanguage: language.map(Self.normalize),
                    containerExtension: video.containerExtension,
                    playbackContentType: Self.playbackContentType(from: video.contentType, indexedAs: contentType),
                    coverImageURL: video.coverImageURL,
                    tmdbId: nil,
                    rating: video.rating,
                    addedAtRaw: addedAtRaw,
                    addedAt: Self.parseDate(addedAtRaw),
                    savedAt: currentDate,
                    lastAccessAt: currentDate
                )
            )
        }

        try upsertRefreshState(
            providerFingerprint: providerFingerprint,
            contentType: rawContentType,
            categoryID: cleanedCategoryID,
            at: currentDate,
            error: nil
        )
        try modelContext.save()
    }

    func removeCategory(
        contentType: XtreamContentType,
        categoryID: String,
        providerFingerprint: String
    ) throws {
        guard contentType == .vod || contentType == .series else { return }

        let rawContentType = contentType.rawValue
        let cleanedCategoryID = categoryID.trimmingCharacters(in: .whitespacesAndNewlines)

        try modelContext.delete(
            model: PersistedStreamRecord.self,
            where: #Predicate {
                $0.providerFingerprint == providerFingerprint &&
                $0.contentType == rawContentType &&
                $0.categoryID == cleanedCategoryID
            }
        )
        try modelContext.delete(
            model: PersistedCategoryRefreshStateRecord.self,
            where: #Predicate {
                $0.providerFingerprint == providerFingerprint &&
                $0.contentType == rawContentType &&
                $0.categoryID == cleanedCategoryID
            }
        )
        try modelContext.save()
    }

    func clear(providerFingerprint: String?) throws {
        if let providerFingerprint {
            try modelContext.delete(
                model: PersistedStreamRecord.self,
                where: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
            try modelContext.delete(
                model: PersistedCategoryRefreshStateRecord.self,
                where: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        } else {
            try modelContext.delete(
                model: PersistedStreamRecord.self,
                where: #Predicate<PersistedStreamRecord> { _ in true }
            )
            try modelContext.delete(
                model: PersistedCategoryRefreshStateRecord.self,
                where: #Predicate<PersistedCategoryRefreshStateRecord> { _ in true }
            )
        }
        try modelContext.save()
    }

    private func upsertRefreshState(
        providerFingerprint: String,
        contentType: String,
        categoryID: String,
        at date: Date,
        error: String?
    ) throws {
        let descriptor = FetchDescriptor<PersistedCategoryRefreshStateRecord>(
            predicate: #Predicate {
                $0.providerFingerprint == providerFingerprint &&
                $0.contentType == contentType &&
                $0.categoryID == categoryID
            }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.lastAttemptedRefreshAt = date
            if let error {
                existing.failureCount += 1
                existing.lastError = error
                let backoff = min(900.0, 15.0 * pow(2.0, Double(existing.failureCount)))
                existing.nextEligibleRefreshAt = date.addingTimeInterval(backoff)
            } else {
                existing.lastSuccessfulRefreshAt = date
                existing.failureCount = 0
                existing.lastError = nil
                existing.nextEligibleRefreshAt = date.addingTimeInterval(6 * 60 * 60)
            }
            return
        }

        modelContext.insert(
            PersistedCategoryRefreshStateRecord(
                id: "\(providerFingerprint)|\(contentType)|\(categoryID)",
                providerFingerprint: providerFingerprint,
                contentType: contentType,
                categoryID: categoryID,
                lastSuccessfulRefreshAt: error == nil ? date : nil,
                lastAttemptedRefreshAt: date,
                nextEligibleRefreshAt: error == nil ? date.addingTimeInterval(6 * 60 * 60) : date.addingTimeInterval(15),
                failureCount: error == nil ? 0 : 1,
                lastError: error
            )
        )
    }

    private static func makeKey(contentType: XtreamContentType, videoID: Int) -> String {
        "\(contentType.rawValue):\(videoID)"
    }

    private static func playbackContentType(from rawValue: String, indexedAs contentType: XtreamContentType) -> String {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "movie" {
            return "movie"
        }
        if let parsed = XtreamContentType(rawValue: normalized) {
            return parsed.playbackPathComponent
        }
        return normalized.isEmpty ? contentType.playbackPathComponent : normalized
    }

    private static func normalize(_ input: String) -> String {
        input
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
