//
//  Catalog.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
//

import Foundation
import SwiftData

enum CatalogError: LocalizedError {
    case missingProviderConfiguration
    case cacheUnavailable

    var errorDescription: String? {
        switch self {
        case .missingProviderConfiguration:
            "Configure your provider in Settings before loading content."
        case .cacheUnavailable:
            "No cached content is available yet."
        }
    }
}

@MainActor
@Observable
final class Catalog {
    private struct ProviderState {
        let revision: Int
        let config: ProviderConfig
        let fingerprint: String
    }

    private struct CategoryTaskKey: Hashable {
        let providerFingerprint: String
        let contentType: XtreamContentType
        let categoryID: String
    }

    private struct RefreshStateSnapshot {
        let contentType: XtreamContentType
        let categoryID: String
        let lastSuccessfulRefreshAt: Date?
        let lastAttemptedRefreshAt: Date?
        let nextEligibleRefreshAt: Date?
        let failureCount: Int
        let lastError: String?
    }

    var vodCategories: [Category] = []
    var seriesCategories: [Category] = []

    var vodCatalog: [Category: [Video]] = [:]
    var seriesCatalog: [Category: [Video]] = [:]
    var liveCatalog: [Category: [Video]] = [:]

    var vodInfo: [Video: VideoInfo] = [:]
    var catalogueRevision = 0

    private var seriesInfoBySeriesID: [Int: XtreamSeries] = [:]
    private var providerRevision: Int
    private var cachedProviderState: ProviderState?
    private var inFlightStreamLoads: [CategoryTaskKey: Task<[CachedVideoDTO], Error>] = [:]

    private let providerStore: ProviderStore
    private let modelContainer: ModelContainer
    private let cacheManager: CatalogCacheManager
    private let metadataCacheManager: CatalogMetadataCacheManager
    private let imagePrefetcher: ImagePrefetching
    private let searchIndexStore: SearchIndexStore
    private let backgroundRefresher: BackgroundCatalogueRefresher

    let activityCenter: BackgroundActivityCenter

    init(
        providerStore: ProviderStore,
        modelContainer: ModelContainer,
        cacheManager: CatalogCacheManager? = nil,
        metadataCacheManager: CatalogMetadataCacheManager? = nil,
        imagePrefetcher: ImagePrefetching? = nil,
        searchIndexStore: SearchIndexStore? = nil,
        activityCenter: BackgroundActivityCenter? = nil,
        backgroundCatalogueRefresher: BackgroundCatalogueRefresher? = nil
    ) {
        self.providerStore = providerStore
        self.modelContainer = modelContainer
        self.cacheManager = cacheManager ?? CatalogCacheManager(
            diskStore: SwiftDataStreamListCacheStore(modelContainer: modelContainer)
        )
        self.metadataCacheManager = metadataCacheManager ?? CatalogMetadataCacheManager(
            diskStore: SwiftDataCatalogMetadataCacheStore(modelContainer: modelContainer)
        )
        self.imagePrefetcher = imagePrefetcher ?? NoopImagePrefetcher()
        self.searchIndexStore = searchIndexStore ?? SearchIndexStore(modelContainer: modelContainer)
        self.activityCenter = activityCenter ?? BackgroundActivityCenter()
        self.backgroundRefresher = backgroundCatalogueRefresher ?? BackgroundCatalogueRefresher()
        self.providerRevision = providerStore.revision
    }

    var hasProviderConfiguration: Bool {
        providerStore.hasConfiguration
    }

    func cachedSeriesInfo(for video: Video) -> XtreamSeries? {
        seriesInfoBySeriesID[video.id]
    }

    func reset() {
        vodCategories = []
        seriesCategories = []
        vodCatalog = [:]
        seriesCatalog = [:]
        liveCatalog = [:]
        vodInfo = [:]
        seriesInfoBySeriesID = [:]
        cachedProviderState = nil
        inFlightStreamLoads.values.forEach { $0.cancel() }
        inFlightStreamLoads.removeAll()
        catalogueRevision += 1

        Task(priority: .utility) {
            await self.cacheManager.clearMemoryCache()
            await self.metadataCacheManager.clearMemoryCache()
            await self.backgroundRefresher.stop()
        }
    }

    func prefetchImages(urls: [URL]) async {
        await imagePrefetcher.prefetch(urls: urls)
    }

    func startBackgroundRefreshing() async {
        guard hasProviderConfiguration, let fingerprint = try? currentProviderFingerprint() else {
            await backgroundRefresher.stop()
            return
        }

        await backgroundRefresher.start(
            providerFingerprint: fingerprint,
            ensureBootstrap: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.ensureBootstrapCategoriesLoaded()
            },
            nextTargets: { [weak self] providerFingerprint in
                guard let self else { return [] }
                return await self.backgroundRefreshTargets(providerFingerprint: providerFingerprint)
            },
            refresh: { [weak self] target in
                guard let self else { throw CancellationError() }
                try await self.refreshBackgroundTarget(target)
            },
            progress: { [weak self] scope, providerFingerprint in
                guard let self else {
                    return SearchIndexProgress(indexedCategories: 0, totalCategories: 0, scope: scope)
                }
                return await self.searchIndexProgress(scope: scope, providerFingerprint: providerFingerprint)
            }
        )
    }

    func stopBackgroundRefreshing() async {
        await backgroundRefresher.stop()
    }

    private func ensureCurrentProvider() {
        guard providerRevision != providerStore.revision else { return }
        providerRevision = providerStore.revision
        reset()
    }

    private func providerState() throws -> ProviderState {
        ensureCurrentProvider()

        if let cachedProviderState, cachedProviderState.revision == providerStore.revision {
            return cachedProviderState
        }

        let config = try providerStore.requiredConfiguration()
        let state = ProviderState(
            revision: providerStore.revision,
            config: config,
            fingerprint: ProviderCacheFingerprint.make(from: config)
        )
        cachedProviderState = state
        return state
    }

    private func currentProviderFingerprint() throws -> String {
        try providerState().fingerprint
    }

    private func service() throws -> XtreamService {
        let state = try providerState()
        return XtreamService(
            .shared,
            baseURL: state.config.apiURL,
            username: state.config.username,
            password: state.config.password
        )
    }

    private func cacheKey(for category: Category, contentType: XtreamContentType) throws -> StreamListCacheKey {
        let state = try providerState()
        return StreamListCacheKey(
            providerFingerprint: state.fingerprint,
            contentType: contentType,
            categoryID: category.id,
            pageToken: nil
        )
    }

    private func metadataKey(kind: CatalogMetadataKind, resourceID: String) throws -> CatalogMetadataCacheKey {
        CatalogMetadataCacheKey(
            providerFingerprint: try currentProviderFingerprint(),
            kind: kind,
            resourceID: resourceID
        )
    }

    private func cacheOnlyFailure(policy: CatalogLoadPolicy, fallbackError: Error? = nil) throws -> Never {
        if case .cacheOnly = policy, let fallbackError {
            throw fallbackError
        }
        throw fallbackError ?? CatalogError.cacheUnavailable
    }

    private func decodeCachedValue<Value: Decodable>(_ type: Value.Type, from payload: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: payload)
        } catch {
            throw NetworkError.invalidResponse
        }
    }

    private func applyCategoryVisibility(to categories: [Category]) -> [Category] {
        categories.filter { !providerStore.isExcludedCategoryPrefix($0.languageGroupCode) }
    }

    private func applyCategories(_ categories: [CachedCategoryDTO], for contentType: XtreamContentType) {
        let visible = applyCategoryVisibility(to: categories.map(Category.init(cached:)))
        switch contentType {
        case .vod:
            vodCategories = visible
            vodCatalog = reboundCatalogStorage(vodCatalog, to: visible)
        case .series:
            seriesCategories = visible
            seriesCatalog = reboundCatalogStorage(seriesCatalog, to: visible)
        case .live:
            break
        }
        catalogueRevision += 1
    }

    private func applyStreams(_ videos: [CachedVideoDTO], in category: Category, contentType: XtreamContentType) {
        let mapped = videos.map(Video.init)
        switch contentType {
        case .vod:
            removeCachedStreams(categoryID: category.id, contentType: .vod)
            vodCatalog[category] = mapped
        case .series:
            removeCachedStreams(categoryID: category.id, contentType: .series)
            seriesCatalog[category] = mapped
        case .live:
            removeCachedStreams(categoryID: category.id, contentType: .live)
            liveCatalog[category] = mapped
        }
        catalogueRevision += 1
    }

    private func reboundCatalogStorage(
        _ storage: [Category: [Video]],
        to categories: [Category]
    ) -> [Category: [Video]] {
        var rebound: [Category: [Video]] = [:]

        for category in categories {
            guard let entry = storage.first(where: { $0.key.id == category.id }) else { continue }
            rebound[category] = entry.value
        }

        return rebound
    }

    private func removeCachedStreams(categoryID: String, contentType: XtreamContentType) {
        switch contentType {
        case .vod:
            vodCatalog = vodCatalog.filter { $0.key.id != categoryID }
        case .series:
            seriesCatalog = seriesCatalog.filter { $0.key.id != categoryID }
        case .live:
            liveCatalog = liveCatalog.filter { $0.key.id != categoryID }
        }
    }

    private func cachedVideosByID(categoryID: String, contentType: XtreamContentType) -> [Video]? {
        switch contentType {
        case .vod:
            vodCatalog.first { $0.key.id == categoryID }?.value
        case .series:
            seriesCatalog.first { $0.key.id == categoryID }?.value
        case .live:
            liveCatalog.first { $0.key.id == categoryID }?.value
        }
    }

    private func fetchCategoryDTOs(for contentType: XtreamContentType) async throws -> [CachedCategoryDTO] {
        try await service().getCategories(of: contentType).map(CachedCategoryDTO.init)
    }

    private func fetchVodStreamDTOs(inCategoryID categoryID: String) async throws -> [CachedVideoDTO] {
        try await service().getStreams(of: .vod, in: categoryID).map(CachedVideoDTO.init)
    }

    private func fetchSeriesStreamDTOs(inCategoryID categoryID: String) async throws -> [CachedVideoDTO] {
        try await service().getSeries(in: categoryID).map(CachedVideoDTO.init)
    }

    private func cachedCategoryDTOs(for key: CatalogMetadataCacheKey) async throws -> [CachedCategoryDTO] {
        guard let cached = try await metadataCacheManager.cachedPayload(for: key) else { return [] }
        return try decodeCachedValue([CachedCategoryDTO].self, from: cached.value)
    }

    private func reconcileCategoryRefresh(
        oldCategories: [CachedCategoryDTO],
        freshCategories: [CachedCategoryDTO],
        contentType: XtreamContentType,
        providerFingerprint: String
    ) async throws {
        let freshIDs = Set(freshCategories.map(\.id))
        let removedCategories = oldCategories.filter { !freshIDs.contains($0.id) }

        for removedCategory in removedCategories {
            let key = StreamListCacheKey(
                providerFingerprint: providerFingerprint,
                contentType: contentType,
                categoryID: removedCategory.id,
                pageToken: nil
            )
            let removedVideos = try await cacheManager.entry(for: key)?.videos ?? []
            try await cacheManager.removeValue(for: key)
            removeCachedStreams(categoryID: removedCategory.id, contentType: contentType)
            deleteCategoryRefreshState(
                providerFingerprint: providerFingerprint,
                contentType: contentType,
                categoryID: removedCategory.id
            )
            await pruneOrphanedDetailMetadata(
                videoIDs: Set(removedVideos.map(\.id)),
                contentType: contentType,
                providerFingerprint: providerFingerprint
            )
        }
    }

    private func pruneOrphanedDetailMetadata(
        videoIDs: Set<Int>,
        contentType: XtreamContentType,
        providerFingerprint: String
    ) async {
        guard contentType == .vod || contentType == .series else { return }

        let entries = (try? await cacheManager.entries(providerFingerprint: providerFingerprint)) ?? []
        let referencedIDs = Set(
            entries
                .filter { $0.key.contentType == contentType }
                .flatMap { $0.videos.map(\.id) }
        )

        for videoID in videoIDs where !referencedIDs.contains(videoID) {
            switch contentType {
            case .vod:
                vodInfo = vodInfo.filter { $0.key.id != videoID }
                if let key = try? metadataKey(kind: .vodInfo, resourceID: String(videoID)) {
                    try? await metadataCacheManager.removeValue(for: key)
                }
            case .series:
                seriesInfoBySeriesID[videoID] = nil
                if let key = try? metadataKey(kind: .seriesInfo, resourceID: String(videoID)) {
                    try? await metadataCacheManager.removeValue(for: key)
                }
            case .live:
                break
            }
        }
    }

    private func loadCategories(
        contentType: XtreamContentType,
        kind: CatalogMetadataKind,
        policy: CatalogLoadPolicy
    ) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }

        let key = try metadataKey(kind: kind, resourceID: "all")
        let cachedPayload = try await metadataCacheManager.cachedPayload(for: key)
        let cached = try cachedPayload.map {
            CatalogCachedValue(
                value: try decodeCachedValue([CachedCategoryDTO].self, from: $0.value),
                savedAt: $0.savedAt
            )
        }

        switch policy {
        case .cacheOnly:
            guard let cached else { try cacheOnlyFailure(policy: policy) }
            applyCategories(cached.value, for: contentType)
        case .readThrough:
            if let cached {
                applyCategories(cached.value, for: contentType)
            } else {
                let fresh = try await refreshCategories(key: key, contentType: contentType)
                applyCategories(fresh, for: contentType)
            }
        case .forceRefresh:
            let fresh = try await refreshCategories(key: key, contentType: contentType)
            applyCategories(fresh, for: contentType)
        }
    }

    private func refreshCategories(
        key: CatalogMetadataCacheKey,
        contentType: XtreamContentType
    ) async throws -> [CachedCategoryDTO] {
        let previous = try await cachedCategoryDTOs(for: key)
        let fresh = try await metadataCacheManager.refreshPayload(for: key) { [weak self] in
            guard let self else { throw CancellationError() }
            return try JSONEncoder().encode(try await self.fetchCategoryDTOs(for: contentType))
        }
        let decoded = try decodeCachedValue([CachedCategoryDTO].self, from: fresh)
        try await reconcileCategoryRefresh(
            oldCategories: previous,
            freshCategories: decoded,
            contentType: contentType,
            providerFingerprint: key.providerFingerprint
        )
        applyCategories(decoded, for: contentType)
        return decoded
    }

    private func loadStreams(
        in category: Category,
        contentType: XtreamContentType,
        policy: CatalogLoadPolicy,
        fetcher: @escaping @Sendable () async throws -> [CachedVideoDTO]
    ) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }

        let key = try cacheKey(for: category, contentType: contentType)
        let cached = try await cacheManager.cachedValue(for: key)

        switch policy {
        case .cacheOnly:
            guard let cached else { try cacheOnlyFailure(policy: policy) }
            applyStreams(cached.value, in: category, contentType: contentType)
        case .readThrough:
            if let cached {
                applyStreams(cached.value, in: category, contentType: contentType)
            } else {
                let fresh = try await fetchAndPersistCategoryStreams(
                    key: key,
                    category: category,
                    contentType: contentType,
                    fetcher: fetcher
                )
                applyStreams(fresh, in: category, contentType: contentType)
            }
        case .forceRefresh:
            let fresh = try await fetchAndPersistCategoryStreams(
                key: key,
                category: category,
                contentType: contentType,
                fetcher: fetcher
            )
            applyStreams(fresh, in: category, contentType: contentType)
        }
    }

    private func fetchAndPersistCategoryStreams(
        key: StreamListCacheKey,
        category: Category,
        contentType: XtreamContentType,
        fetcher: @escaping @Sendable () async throws -> [CachedVideoDTO]
    ) async throws -> [CachedVideoDTO] {
        let taskKey = CategoryTaskKey(
            providerFingerprint: key.providerFingerprint,
            contentType: contentType,
            categoryID: category.id
        )

        if let inFlight = inFlightStreamLoads[taskKey] {
            return try await inFlight.value
        }

        let task = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { throw CancellationError() }

            let previousVideos = try await self.cacheManager.entry(for: key)?.videos ?? []
            self.recordCategoryRefreshAttempt(
                providerFingerprint: key.providerFingerprint,
                contentType: contentType,
                categoryID: category.id
            )

            do {
                let fresh = try await self.cacheManager.refreshValue(for: key, fetcher: fetcher)
                self.recordCategoryRefreshSuccess(
                    providerFingerprint: key.providerFingerprint,
                    contentType: contentType,
                    categoryID: category.id
                )
                let removedVideoIDs = Set(previousVideos.map(\.id)).subtracting(fresh.map(\.id))
                await self.pruneOrphanedDetailMetadata(
                    videoIDs: removedVideoIDs,
                    contentType: contentType,
                    providerFingerprint: key.providerFingerprint
                )
                self.catalogueRevision += 1
                return fresh
            } catch {
                self.recordCategoryRefreshFailure(
                    providerFingerprint: key.providerFingerprint,
                    contentType: contentType,
                    categoryID: category.id,
                    error: error.localizedDescription
                )
                throw error
            }
        }

        inFlightStreamLoads[taskKey] = task
        defer {
            inFlightStreamLoads[taskKey] = nil
        }

        return try await task.value
    }

    private func loadVodInfo(_ video: Video, policy: CatalogLoadPolicy) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }

        let key = try metadataKey(kind: .vodInfo, resourceID: String(video.id))
        let cachedPayload = try await metadataCacheManager.cachedPayload(for: key)
        let cached = try cachedPayload.map {
            CatalogCachedValue(
                value: try decodeCachedValue(CachedVideoInfoDTO.self, from: $0.value),
                savedAt: $0.savedAt
            )
        }

        switch policy {
        case .cacheOnly:
            guard let cached else { try cacheOnlyFailure(policy: policy) }
            vodInfo[video] = VideoInfo(cached: cached.value)
        case .readThrough:
            if let cached {
                vodInfo[video] = VideoInfo(cached: cached.value)
            } else {
                vodInfo[video] = VideoInfo(cached: try await refreshVodInfo(video, key: key))
            }
        case .forceRefresh:
            vodInfo[video] = VideoInfo(cached: try await refreshVodInfo(video, key: key))
        }
    }

    private func refreshVodInfo(_ video: Video, key: CatalogMetadataCacheKey) async throws -> CachedVideoInfoDTO {
        let fresh = try await metadataCacheManager.refreshPayload(for: key) { [weak self] in
            guard let self else { throw CancellationError() }
            let dto = try await self.service().getVodInfo(of: String(video.id))
            return try JSONEncoder().encode(CachedVideoInfoDTO(VideoInfo(from: dto)))
        }
        let decoded = try decodeCachedValue(CachedVideoInfoDTO.self, from: fresh)
        vodInfo[video] = VideoInfo(cached: decoded)
        return decoded
    }

    private func loadSeriesInfo(_ video: Video, policy: CatalogLoadPolicy) async throws -> XtreamSeries {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }

        let key = try metadataKey(kind: .seriesInfo, resourceID: String(video.id))
        let cachedPayload = try await metadataCacheManager.cachedPayload(for: key)
        let cached = try cachedPayload.map {
            CatalogCachedValue(
                value: try decodeCachedValue(XtreamSeries.self, from: $0.value),
                savedAt: $0.savedAt
            )
        }

        switch policy {
        case .cacheOnly:
            guard let cached else { try cacheOnlyFailure(policy: policy) }
            seriesInfoBySeriesID[video.id] = cached.value
            return cached.value
        case .readThrough:
            if let cached {
                seriesInfoBySeriesID[video.id] = cached.value
                return cached.value
            }
        case .forceRefresh:
            break
        }

        let fresh = try await refreshSeriesInfo(video, key: key)
        seriesInfoBySeriesID[video.id] = fresh
        return fresh
    }

    private func refreshSeriesInfo(_ video: Video, key: CatalogMetadataCacheKey) async throws -> XtreamSeries {
        let fresh = try await metadataCacheManager.refreshPayload(for: key) { [weak self] in
            guard let self else { throw CancellationError() }
            return try JSONEncoder().encode(try await self.service().getSeriesInfo(of: String(video.id)))
        }
        let decoded = try decodeCachedValue(XtreamSeries.self, from: fresh)
        seriesInfoBySeriesID[video.id] = decoded
        return decoded
    }

    private func ensureBootstrapCategoriesLoaded() async throws {
        try await getVodCategories(policy: .readThrough)
        try await getSeriesCategories(policy: .readThrough)
    }

    private func backgroundRefreshTargets(providerFingerprint: String) async -> [BackgroundCatalogueRefreshTarget] {
        let states = refreshStates(providerFingerprint: providerFingerprint)
        let now = Date()
        let staleThreshold = now.addingTimeInterval(-(6 * 60 * 60))

        let movieTargets = vodCategories.enumerated().compactMap { index, category in
            makeRefreshTarget(
                providerFingerprint: providerFingerprint,
                contentType: .vod,
                category: category,
                sortIndex: index,
                states: states,
                staleThreshold: staleThreshold,
                now: now
            )
        }
        let seriesTargets = seriesCategories.enumerated().compactMap { index, category in
            makeRefreshTarget(
                providerFingerprint: providerFingerprint,
                contentType: .series,
                category: category,
                sortIndex: index,
                states: states,
                staleThreshold: staleThreshold,
                now: now
            )
        }

        return movieTargets + seriesTargets
    }

    private func makeRefreshTarget(
        providerFingerprint: String,
        contentType: XtreamContentType,
        category: Category,
        sortIndex: Int,
        states: [String: RefreshStateSnapshot],
        staleThreshold: Date,
        now: Date
    ) -> BackgroundCatalogueRefreshTarget? {
        let stateKey = refreshStateKey(contentType: contentType, categoryID: category.id)
        let state = states[stateKey]

        if let nextEligibleRefreshAt = state?.nextEligibleRefreshAt, nextEligibleRefreshAt > now {
            return nil
        }

        if let lastSuccessfulRefreshAt = state?.lastSuccessfulRefreshAt,
           lastSuccessfulRefreshAt > staleThreshold {
            return nil
        }

        return BackgroundCatalogueRefreshTarget(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: category.id,
            categoryName: category.name,
            sortIndex: sortIndex
        )
    }

    private func refreshBackgroundTarget(_ target: BackgroundCatalogueRefreshTarget) async throws {
        try await activityCenter.waitIfResumed()
        let category = categories(for: target.contentType).first(where: { $0.id == target.categoryID })
            ?? Category(id: target.categoryID, name: target.categoryName)
        try await getStreams(in: category, contentType: target.contentType, policy: .forceRefresh)
    }

    private func refreshStates(providerFingerprint: String) -> [String: RefreshStateSnapshot] {
        let context = ModelContext(modelContainer)
        let records = (try? context.fetch(
            FetchDescriptor<PersistedCategoryRefreshStateRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )) ?? []

        return Dictionary(
            uniqueKeysWithValues: records.compactMap { record in
                guard let contentType = XtreamContentType(rawValue: record.contentType) else { return nil }
                return (
                    refreshStateKey(contentType: contentType, categoryID: record.categoryID),
                    RefreshStateSnapshot(
                        contentType: contentType,
                        categoryID: record.categoryID,
                        lastSuccessfulRefreshAt: record.lastSuccessfulRefreshAt,
                        lastAttemptedRefreshAt: record.lastAttemptedRefreshAt,
                        nextEligibleRefreshAt: record.nextEligibleRefreshAt,
                        failureCount: record.failureCount,
                        lastError: record.lastError
                    )
                )
            }
        )
    }

    private func refreshStateRecord(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String,
        context: ModelContext
    ) -> PersistedCategoryRefreshStateRecord? {
        let rawContentType = contentType.rawValue
        return try? context.fetch(
            FetchDescriptor<PersistedCategoryRefreshStateRecord>(
                predicate: #Predicate {
                    $0.providerFingerprint == providerFingerprint &&
                    $0.contentType == rawContentType &&
                    $0.categoryID == categoryID
                }
            )
        ).first
    }

    private func recordCategoryRefreshAttempt(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String
    ) {
        let context = ModelContext(modelContainer)
        let timestamp = Date()

        if let record = refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID,
            context: context
        ) {
            record.lastAttemptedRefreshAt = timestamp
        } else {
            context.insert(
                PersistedCategoryRefreshStateRecord(
                    id: "\(providerFingerprint)|\(contentType.rawValue)|\(categoryID)",
                    providerFingerprint: providerFingerprint,
                    contentType: contentType.rawValue,
                    categoryID: categoryID,
                    lastSuccessfulRefreshAt: nil,
                    lastAttemptedRefreshAt: timestamp,
                    nextEligibleRefreshAt: nil,
                    failureCount: 0,
                    lastError: nil
                )
            )
        }

        try? context.save()
    }

    private func recordCategoryRefreshSuccess(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String
    ) {
        let context = ModelContext(modelContainer)
        let timestamp = Date()
        let record = refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID,
            context: context
        ) ?? PersistedCategoryRefreshStateRecord(
            id: "\(providerFingerprint)|\(contentType.rawValue)|\(categoryID)",
            providerFingerprint: providerFingerprint,
            contentType: contentType.rawValue,
            categoryID: categoryID,
            lastSuccessfulRefreshAt: nil,
            lastAttemptedRefreshAt: nil,
            nextEligibleRefreshAt: nil,
            failureCount: 0,
            lastError: nil
        )

        if refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID,
            context: context
        ) == nil {
            context.insert(record)
        }

        record.lastSuccessfulRefreshAt = timestamp
        record.lastAttemptedRefreshAt = timestamp
        record.nextEligibleRefreshAt = timestamp.addingTimeInterval(6 * 60 * 60)
        record.failureCount = 0
        record.lastError = nil
        try? context.save()
    }

    private func recordCategoryRefreshFailure(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String,
        error: String
    ) {
        let context = ModelContext(modelContainer)
        let timestamp = Date()
        let record = refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID,
            context: context
        ) ?? PersistedCategoryRefreshStateRecord(
            id: "\(providerFingerprint)|\(contentType.rawValue)|\(categoryID)",
            providerFingerprint: providerFingerprint,
            contentType: contentType.rawValue,
            categoryID: categoryID,
            lastSuccessfulRefreshAt: nil,
            lastAttemptedRefreshAt: nil,
            nextEligibleRefreshAt: nil,
            failureCount: 0,
            lastError: nil
        )

        if refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID,
            context: context
        ) == nil {
            context.insert(record)
        }

        record.lastAttemptedRefreshAt = timestamp
        record.failureCount += 1
        record.lastError = error
        let backoff = min(900.0, 15.0 * pow(2.0, Double(record.failureCount)))
        record.nextEligibleRefreshAt = timestamp.addingTimeInterval(backoff)
        try? context.save()
    }

    private func deleteCategoryRefreshState(
        providerFingerprint: String,
        contentType: XtreamContentType,
        categoryID: String
    ) {
        let context = ModelContext(modelContainer)
        if let record = refreshStateRecord(
            providerFingerprint: providerFingerprint,
            contentType: contentType,
            categoryID: categoryID,
            context: context
        ) {
            context.delete(record)
            try? context.save()
        }
    }

    private func refreshStateKey(contentType: XtreamContentType, categoryID: String) -> String {
        "\(contentType.rawValue):\(categoryID)"
    }

    private func storedCategoryCount(scope: SearchMediaScope, providerFingerprint: String) -> Int {
        let acceptedTypes = Set(scope.acceptedContentTypes.map(\.rawValue))
        let context = ModelContext(modelContainer)
        let records = (try? context.fetch(
            FetchDescriptor<PersistedCategoryRecord>(
                predicate: #Predicate { $0.providerFingerprint == providerFingerprint }
            )
        )) ?? []
        return records.filter { acceptedTypes.contains($0.contentType) }.count
    }

    private func totalCategoryCount(for scope: SearchMediaScope, providerFingerprint: String? = nil) -> Int {
        switch scope {
        case .all:
            let inMemory = vodCategories.count + seriesCategories.count
            if inMemory > 0 { return inMemory }
        case .movies:
            if !vodCategories.isEmpty { return vodCategories.count }
        case .series:
            if !seriesCategories.isEmpty { return seriesCategories.count }
        }

        guard let providerFingerprint else { return 0 }
        return storedCategoryCount(scope: scope, providerFingerprint: providerFingerprint)
    }

    private func searchIndexProgress(scope: SearchMediaScope, providerFingerprint: String) async -> SearchIndexProgress {
        await searchIndexStore.progress(
            scope: scope,
            providerFingerprint: providerFingerprint,
            totalCategories: totalCategoryCount(for: scope, providerFingerprint: providerFingerprint)
        )
    }
}

extension Catalog {
    func getVodCategories(force: Bool = false) async throws {
        try await getVodCategories(policy: force ? .forceRefresh : .readThrough)
    }

    func getSeriesCategories(force: Bool = false) async throws {
        try await getSeriesCategories(policy: force ? .forceRefresh : .readThrough)
    }

    func getVodStreams(in category: Category, force: Bool = false) async throws {
        try await getVodStreams(in: category, policy: force ? .forceRefresh : .readThrough)
    }

    func getSeriesStreams(in category: Category, force: Bool = false) async throws {
        try await getSeriesStreams(in: category, policy: force ? .forceRefresh : .readThrough)
    }

    func getVodInfo(_ video: Video, force: Bool = false) async throws {
        try await getVodInfo(video, policy: force ? .forceRefresh : .readThrough)
    }

    func getSeriesInfo(_ video: Video, force: Bool = false) async throws -> XtreamSeries {
        try await getSeriesInfo(video, policy: force ? .forceRefresh : .readThrough)
    }

    func resolveURL(for video: Video) throws -> URL {
        try service().getPlayURL(for: video.id, type: video.contentType, containerExtension: video.containerExtension)
    }

    func resolveEpisodeDownloadURL(
        seriesID: Int,
        episodeVideoID: Int,
        containerExtension: String,
        directSource: String
    ) throws -> URL {
        let normalizedDirectSource = directSource.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedDirectSource.isEmpty, let directURL = URL(string: normalizedDirectSource) {
            return directURL
        }

        return try service().getPlayURL(
            for: episodeVideoID,
            type: XtreamContentType.series.rawValue,
            containerExtension: containerExtension
        )
    }

    func prepareDownloadMetadata(for video: Video) async throws -> DownloadPreparedMetadata {
        switch video.xtreamContentType {
        case .vod:
            try await getVodInfo(video, policy: .readThrough)
            let resolvedInfo = vodInfo[video] ?? VideoInfo(
                images: [],
                plot: "",
                cast: "",
                director: "",
                genre: "",
                releaseDate: "",
                durationLabel: "",
                runtimeMinutes: nil,
                ageRating: "",
                country: "",
                rating: video.rating
            )

            let artworkURLs = Array(
                Set(
                    resolvedInfo.images +
                    [video.coverImageURL].compactMap { $0 }.compactMap(URL.init(string:))
                )
            )

            return DownloadPreparedMetadata(
                snapshotID: DownloadIdentifiers.metadataSnapshotID(
                    scope: DownloadScope(
                        profileID: "primary",
                        providerFingerprint: try currentProviderFingerprint()
                    ),
                    contentType: video.contentType,
                    videoID: video.id
                ),
                kind: .movie,
                videoID: video.id,
                contentType: video.contentType,
                title: video.name,
                coverImageURL: video.coverImageURL,
                artworkURLs: artworkURLs,
                movieInfo: CachedVideoInfoDTO(resolvedInfo),
                seriesInfo: nil
            )

        case .series:
            let seriesInfo = try await getSeriesInfo(video, policy: .readThrough)
            let artworkURLs = Array(
                Set(
                    [
                        seriesInfo.info.backdropPath.first,
                        seriesInfo.info.cover,
                        video.coverImageURL
                    ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .compactMap(URL.init(string:)) +
                    seriesInfo.episodes.values
                        .flatMap { $0 }
                        .compactMap { episode in
                            let value = episode.info.movieImage.trimmingCharacters(in: .whitespacesAndNewlines)
                            return value.isEmpty ? nil : URL(string: value)
                        }
                )
            )

            return DownloadPreparedMetadata(
                snapshotID: DownloadIdentifiers.metadataSnapshotID(
                    scope: DownloadScope(
                        profileID: "primary",
                        providerFingerprint: try currentProviderFingerprint()
                    ),
                    contentType: video.contentType,
                    videoID: video.id
                ),
                kind: .series,
                videoID: video.id,
                contentType: video.contentType,
                title: seriesInfo.info.name.isEmpty ? video.name : seriesInfo.info.name,
                coverImageURL: video.coverImageURL,
                artworkURLs: artworkURLs,
                movieInfo: nil,
                seriesInfo: seriesInfo
            )

        case .live:
            throw DownloadRuntimeError.unsupportedContent
        }
    }

    func search(_ query: SearchQuery) async throws -> [SearchResultItem] {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        return await searchIndexStore.query(query, providerFingerprint: try currentProviderFingerprint())
    }

    func searchFacetValues(scope: SearchMediaScope) async throws -> SearchFacetValues {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        return await searchIndexStore.facetValues(scope: scope, providerFingerprint: try currentProviderFingerprint())
    }

    func searchIndexProgress(scope: SearchMediaScope) async throws -> SearchIndexProgress {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        return await searchIndexProgress(scope: scope, providerFingerprint: try currentProviderFingerprint())
    }

    func providerCatalogueSummary() async throws -> ProviderCatalogueSummary {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        let fingerprint = try currentProviderFingerprint()
        if vodCategories.isEmpty {
            try await getVodCategories(policy: .readThrough)
        }
        if seriesCategories.isEmpty {
            try await getSeriesCategories(policy: .readThrough)
        }

        let counts = await searchIndexStore.providerCounts(providerFingerprint: fingerprint)
        let indexedMovies = await searchIndexStore.indexedCategories(scope: .movies, providerFingerprint: fingerprint).count
        let indexedSeries = await searchIndexStore.indexedCategories(scope: .series, providerFingerprint: fingerprint).count

        return ProviderCatalogueSummary(
            movieCount: counts.movies,
            seriesCount: counts.series,
            indexedMovieCategories: indexedMovies,
            totalMovieCategories: totalCategoryCount(for: .movies, providerFingerprint: fingerprint),
            indexedSeriesCategories: indexedSeries,
            totalSeriesCategories: totalCategoryCount(for: .series, providerFingerprint: fingerprint)
        )
    }

    func runBackgroundCatalogueIndex(forceRefresh: Bool = false) async throws {
        guard hasProviderConfiguration else { throw CatalogError.missingProviderConfiguration }
        let fingerprint = try currentProviderFingerprint()

        if forceRefresh {
            try await getVodCategories(policy: .forceRefresh)
            try await getSeriesCategories(policy: .forceRefresh)
        } else {
            try await ensureBootstrapCategoriesLoaded()
        }

        let targets = forceRefresh
            ? vodCategories.enumerated().map {
                BackgroundCatalogueRefreshTarget(
                    providerFingerprint: fingerprint,
                    contentType: .vod,
                    categoryID: $0.element.id,
                    categoryName: $0.element.name,
                    sortIndex: $0.offset
                )
            } + seriesCategories.enumerated().map {
                BackgroundCatalogueRefreshTarget(
                    providerFingerprint: fingerprint,
                    contentType: .series,
                    categoryID: $0.element.id,
                    categoryName: $0.element.name,
                    sortIndex: $0.offset
                )
            }
            : await backgroundRefreshTargets(providerFingerprint: fingerprint)

        guard !targets.isEmpty else { return }

        let activityID = "background-refresh:\(fingerprint)"
        activityCenter.start(
            id: activityID,
            title: "Refreshing Catalogue",
            detail: nil,
            source: "Library",
            progress: (0, max(targets.count, 1))
        )

        do {
            for (index, target) in targets.enumerated() {
                try await activityCenter.waitIfResumed()
                try await refreshBackgroundTarget(target)
                activityCenter.update(
                    id: activityID,
                    detail: target.categoryName,
                    progress: (index + 1, max(targets.count, 1))
                )
            }
            activityCenter.finish(id: activityID, detail: "Up to date")
        } catch is CancellationError {
            activityCenter.cancel(id: activityID)
            throw CancellationError()
        } catch {
            activityCenter.fail(id: activityID, error: error)
            throw error
        }
    }

    func ensureSearchCoverage(scope: SearchMediaScope) -> AsyncStream<SearchIndexProgress> {
        AsyncStream { continuation in
            Task { @MainActor in
                guard hasProviderConfiguration else {
                    continuation.yield(SearchIndexProgress(indexedCategories: 0, totalCategories: 0, scope: scope))
                    continuation.finish()
                    return
                }

                await startBackgroundRefreshing()
                let providerFingerprint = (try? currentProviderFingerprint()) ?? ""
                let stream = await backgroundRefresher.observeProgress(
                    scope: scope,
                    providerFingerprint: providerFingerprint
                ) { [weak self] scope, providerFingerprint in
                    guard let self else {
                        return SearchIndexProgress(indexedCategories: 0, totalCategories: 0, scope: scope)
                    }
                    return await self.searchIndexProgress(scope: scope, providerFingerprint: providerFingerprint)
                }

                for await progress in stream {
                    continuation.yield(progress)
                }

                continuation.finish()
            }
        }
    }

    func clearSearchIndex() async {
        catalogueRevision += 1
    }

    func getVodCategories(policy: CatalogLoadPolicy = .readThrough) async throws {
        try await loadCategories(contentType: .vod, kind: .vodCategories, policy: policy)
    }

    func getSeriesCategories(policy: CatalogLoadPolicy = .readThrough) async throws {
        try await loadCategories(contentType: .series, kind: .seriesCategories, policy: policy)
    }

    func getVodStreams(in category: Category, policy: CatalogLoadPolicy = .readThrough) async throws {
        let categoryID = category.id
        try await loadStreams(in: category, contentType: .vod, policy: policy) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchVodStreamDTOs(inCategoryID: categoryID)
        }
    }

    func getSeriesStreams(in category: Category, policy: CatalogLoadPolicy = .readThrough) async throws {
        let categoryID = category.id
        try await loadStreams(in: category, contentType: .series, policy: policy) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchSeriesStreamDTOs(inCategoryID: categoryID)
        }
    }

    func getVodInfo(_ video: Video, policy: CatalogLoadPolicy = .readThrough) async throws {
        try await loadVodInfo(video, policy: policy)
    }

    func getSeriesInfo(_ video: Video, policy: CatalogLoadPolicy = .readThrough) async throws -> XtreamSeries {
        try await loadSeriesInfo(video, policy: policy)
    }

    func clearProviderCaches() async throws {
        guard let fingerprint = try? currentProviderFingerprint() else {
            reset()
            return
        }

        await cacheManager.clearMemoryCache()
        await metadataCacheManager.clearMemoryCache()
        try await cacheManager.removeAll(for: fingerprint)
        try await metadataCacheManager.removeAll(for: fingerprint)
        await searchIndexStore.clear(providerFingerprint: fingerprint)
        reset()
    }

    func clearMediaCache() {
        URLCache.shared.removeAllCachedResponses()
    }

    func rebuildSearchIndexFromCachedMetadata() async throws {
        catalogueRevision += 1
    }

    func refreshCurrentProvider() async throws {
        try await getVodCategories(policy: .forceRefresh)
        try await getSeriesCategories(policy: .forceRefresh)
    }

    func categories(for contentType: XtreamContentType) -> [Category] {
        switch contentType {
        case .vod:
            vodCategories
        case .series:
            seriesCategories
        case .live:
            []
        }
    }

    func cachedVideos(in category: Category, contentType: XtreamContentType) -> [Video]? {
        cachedVideosByID(categoryID: category.id, contentType: contentType)
    }

    func getCategories(for contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws {
        switch contentType {
        case .vod:
            try await getVodCategories(policy: policy)
        case .series:
            try await getSeriesCategories(policy: policy)
        case .live:
            break
        }
    }

    func getCategories(for contentType: XtreamContentType, force: Bool = false) async throws {
        try await getCategories(for: contentType, policy: force ? .forceRefresh : .readThrough)
    }

    func getStreams(in category: Category, contentType: XtreamContentType, policy: CatalogLoadPolicy) async throws {
        switch contentType {
        case .vod:
            try await getVodStreams(in: category, policy: policy)
        case .series:
            try await getSeriesStreams(in: category, policy: policy)
        case .live:
            break
        }
    }

    func getStreams(in category: Category, contentType: XtreamContentType, force: Bool = false) async throws {
        try await getStreams(in: category, contentType: contentType, policy: force ? .forceRefresh : .readThrough)
    }
}
