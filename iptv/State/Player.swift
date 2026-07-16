/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model object that manages stream playback and backend fallback.
*/

import AVFoundation
import Dependencies
import Foundation
import Observation
import OSLog
import SQLiteData

private nonisolated let logger = Logger(subsystem: "IPTV", category: "Player")

/// The presentation modes the player supports.
enum Presentation {
    /// Presents the player as a child of a parent user interface.
    case inline
    /// Presents the player in full-window exclusive mode.
    case fullWindow
}

private enum PlayerFeature: CaseIterable {
    case audioTracks
    case subtitles
    case quality
    case chapters
    case outputRoute
    case audioDelay
    case brightness
}

@MainActor
@Observable
final class Player {
    private(set) var playbackState: PlaybackState = .idle
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var isPlaybackComplete = false
    private(set) var presentation: Presentation = .inline
    private(set) var currentItem: Media?
    private(set) var currentTime: Double = 0
    private(set) var duration: Double?
    private(set) var errorMessage: String?
    private(set) var activeBackendID: PlaybackBackendID?
    private(set) var rendererRevision = 0
    private(set) var shouldAutoPlay = true
    private(set) var isCatchupPlayback = false

    private(set) var capabilities: PlaybackCapabilities = .unsupported
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var qualityVariants: [QualityVariant] = [QualityVariant.auto]
    private(set) var chapterMarkers: [ChapterMarker] = []
    private(set) var outputRoutes: [OutputRoute] = []

    private(set) var selectedAudioTrackID: String?
    private(set) var selectedSubtitleTrackID = MediaTrack.subtitleOffID
    private(set) var selectedQualityVariantID = QualityVariant.auto.id
    private(set) var selectedOutputRouteID: String?

    private(set) var playbackSpeed: Double = 1
    private(set) var aspectRatioMode: PlayerAspectRatioMode = .fit
    private(set) var supportedAspectRatioModes: [PlayerAspectRatioMode] = [.fit]
    private(set) var audioDelayMilliseconds = 0
    private(set) var volume: Double = 1
    private(set) var brightness: Double = 0.5

    private(set) var sleepTimerOption: SleepTimerOption = .off
    private(set) var sleepTimerEndsAt: Date?

    private(set) var controlMessage: String?
    private(set) var canRetryEpisodeSwitch = false
    private(set) var liveChannelQueue: [Media] = []

    var progressFraction: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var formattedCurrentTime: String {
        Self.formatTime(currentTime)
    }

    var formattedDuration: String {
        Self.formatTime(duration ?? 0)
    }

    var formattedRemainingTime: String {
        let total = duration ?? 0
        let remaining = max(0, total - currentTime)
        return "-\(Self.formatTime(remaining))"
    }

    var unsupportedFeaturesSummary: String? {
        var features: [String] = []
        if !capabilities.supportsAudioTracks { features.append("Audio tracks") }
        if !capabilities.supportsSubtitles { features.append("Subtitles") }
        if !capabilities.supportsQualitySelection { features.append("Quality") }
        if !capabilities.supportsChapterMarkers { features.append("Chapters") }
        if !capabilities.supportsOutputRouteSelection { features.append("Output route") }
        if !capabilities.supportsAudioDelay { features.append("Audio delay") }

        #if os(iOS) || os(tvOS)
        if !capabilities.supportsBrightness { features.append("Brightness") }
        #endif

        guard !features.isEmpty else { return nil }
        return "Unavailable for current stream/backend: \(features.joined(separator: ", "))."
    }

    var unavailableFeatureMessages: [String] {
        guard currentItem != nil else { return [] }
        return PlayerFeature.allCases.compactMap(unavailableReason(for:))
    }

    @ObservationIgnored
    private let backendFactory: PlaybackBackendFactory
    @ObservationIgnored
    private let database: any DatabaseWriter
    @ObservationIgnored
    private let playbackSourceResolver: any MediaPlaybackSourceResolving
    private let defaults: UserDefaults
    private var backend: (any PlaybackBackend)?
    private var eventTask: Task<Void, Never>?
    private var sleepTimerTask: Task<Void, Never>?
    private var didFallbackForCurrentItem = false
    private var isAirPlayHandoffInProgress = false
    private var lastScheduledProgressByVideoKey: [String: (time: Double, fraction: Double)] = [:]
    private var lastPersistedProgressByVideoKey: [String: (time: Double, fraction: Double)] = [:]
    private var progressWriteTask: Task<Void, Never>?
    private var progressWriteSessionStartedAt = Date.distantPast
    private var progressWriteGeneration: UInt64 = 0
    private var preferredAudioLanguageCode: String?
    private var preferredSubtitleLanguageCode: String?
    private var subtitleEnabledByDefault = false
    private var didApplyAudioPreferenceForCurrentItem = false
    private var didApplySubtitlePreferenceForCurrentItem = false
    private(set) var currentProviderID: Provider.ID?
    private var pendingResumeTime: Double?
    private var pendingHandoffTime: Double?
    private var currentPlaybackURL: URL?
    private var handoffProgressFloor: Double?
    private var lastEpisodeSwitchAttemptID: Int?
    @ObservationIgnored
    private let credentialStore: any ProviderCredentialStoring
    @ObservationIgnored
    private weak var destinationCoordinator: PlaybackDestinationCoordinator?

    init(
        backendFactory: PlaybackBackendFactory? = nil,
        database: (any DatabaseWriter)? = nil,
        playbackSourceResolver: (any MediaPlaybackSourceResolving)? = nil,
        credentialStore: any ProviderCredentialStoring = KeychainProviderCredentialStore(),
        defaults: UserDefaults = .standard
    ) {
        @Dependency(\.defaultDatabase) var defaultDatabase
        self.backendFactory = backendFactory ?? PlaybackBackendFactory()
        self.database = database ?? defaultDatabase
        self.playbackSourceResolver = playbackSourceResolver ?? XtreamMediaPlaybackSourceResolver()
        self.credentialStore = credentialStore
        self.defaults = defaults
        loadSavedPreferencesForCurrentProfile()
    }

    var vlcRenderer: VLCPlayerReference? {
        (backend as? VLCPlaybackBackend)?.player
    }

    var vlcBackend: VLCPlaybackBackend? {
        backend as? VLCPlaybackBackend
    }

    var avRenderer: AVPlayer? {
        (backend as? AVPlaybackBackend)?.player
    }

    /// Loads a stream for playback in the requested presentation.
    func load(
        _ media: Media,
        presentation: Presentation,
        autoplay: Bool = true,
        sourceURL: URL? = nil
    ) {
        persistProgressIfNeeded(force: true)
        deactivateBackend()
        currentPlaybackURL = nil
        currentItem = media
        isCatchupPlayback = sourceURL != nil && media.type == .live
        currentProviderID = nil
        pendingResumeTime = nil
        shouldAutoPlay = autoplay
        didFallbackForCurrentItem = false
        isAirPlayHandoffInProgress = false
        isPlaybackComplete = false
        isPlaying = false
        isBuffering = false
        errorMessage = nil
        controlMessage = nil
        canRetryEpisodeSwitch = false
        lastEpisodeSwitchAttemptID = nil
        currentTime = 0
        duration = nil
        playbackState = .loading
        self.presentation = presentation
        didApplyAudioPreferenceForCurrentItem = false
        didApplySubtitlePreferenceForCurrentItem = false
        pendingHandoffTime = nil
        handoffProgressFloor = nil
        capabilities = .unsupported
        audioTracks = []
        subtitleTracks = []
        qualityVariants = [QualityVariant.auto]
        chapterMarkers = []
        outputRoutes = []
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = MediaTrack.subtitleOffID
        selectedQualityVariantID = QualityVariant.auto.id
        selectedOutputRouteID = nil
        supportedAspectRatioModes = [.fit]

        loadSavedPreferencesForCurrentProfile()
        if media.type == .live {
            playbackSpeed = 1
        }

        do {
            let provider = try activeProvider()
            currentProviderID = provider.id
            beginProgressWriteSession()
            pendingResumeTime = WatchActivityStore.resumeTime(
                for: media,
                providerID: provider.id,
                database: database
            )
            let url: URL
            if let sourceURL {
                url = sourceURL
            } else if let localURL = DownloadStore.localPlaybackURL(
                for: media,
                providerID: provider.id,
                database: database
            ) {
                url = localURL
            } else {
                url = try playbackSourceResolver.playbackURL(for: media, provider: provider)
            }
            currentPlaybackURL = url
            try activateBackend(for: url)
            try backend?.load(url: url, autoplay: autoplay)
            logger.info("Playback started with backend \(self.activeBackendID?.rawValue ?? "unknown", privacy: .public)")
        } catch {
            processTerminalFailure(error)
        }
    }

    func download(_ media: Media) throws {
        let provider = try activeProvider()
        let remoteURL = try playbackSourceResolver.playbackURL(for: media, provider: provider)
        try DownloadCoordinator.shared.enqueue(
            media,
            providerID: provider.id,
            remoteURL: remoteURL,
            database: database
        )
    }

    func loadRemote(_ media: Media, presentation: Presentation = .fullWindow) {
        do {
            let provider = try activeProvider()
            let url = try playbackSourceResolver.playbackURL(for: media, provider: provider)
            load(media, presentation: presentation, sourceURL: url)
        } catch {
            processTerminalFailure(error)
        }
    }

    func loadLiveChannel(_ channel: Media, channels: [Media], presentation: Presentation = .fullWindow) {
        liveChannelQueue = channels.filter { $0.type == .live }
        load(channel, presentation: presentation)
    }

    func zapLiveChannel(by offset: Int) {
        guard let currentItem,
              currentItem.type == .live,
              liveChannelQueue.count > 1,
              let index = liveChannelQueue.firstIndex(where: { $0.id == currentItem.id })
        else {
            controlMessage = "No other channel is available in this list."
            return
        }
        let count = liveChannelQueue.count
        let nextIndex = (index + offset % count + count) % count
        load(liveChannelQueue[nextIndex], presentation: presentation)
    }

    /// Clears any loaded media and resets the player model to its default state.
    func reset() {
        persistProgressIfNeeded(force: true)

        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerOption = .off
        sleepTimerEndsAt = nil

        deactivateBackend()

        currentItem = nil
        currentProviderID = nil
        pendingResumeTime = nil
        pendingHandoffTime = nil
        currentPlaybackURL = nil
        handoffProgressFloor = nil
        shouldAutoPlay = true
        didFallbackForCurrentItem = false
        isAirPlayHandoffInProgress = false
        isPlaybackComplete = false
        isPlaying = false
        isBuffering = false
        currentTime = 0
        duration = nil
        errorMessage = nil
        controlMessage = nil
        canRetryEpisodeSwitch = false
        lastEpisodeSwitchAttemptID = nil
        playbackState = .idle
        presentation = .inline

        capabilities = .unsupported
        audioTracks = []
        subtitleTracks = []
        qualityVariants = [QualityVariant.auto]
        chapterMarkers = []
        outputRoutes = []

        selectedAudioTrackID = nil
        selectedSubtitleTrackID = MediaTrack.subtitleOffID
        selectedQualityVariantID = QualityVariant.auto.id
        selectedOutputRouteID = nil

        playbackSpeed = 1
        aspectRatioMode = .fit
        supportedAspectRatioModes = [.fit]
        audioDelayMilliseconds = 0
        volume = 1
        brightness = 0.5

        didApplyAudioPreferenceForCurrentItem = false
        didApplySubtitlePreferenceForCurrentItem = false
        lastScheduledProgressByVideoKey.removeAll()
        lastPersistedProgressByVideoKey.removeAll()
    }

    func close() {
        reset()
    }

    /// Dismisses the expanded controller without ending logical playback.
    func dismissController() {
        presentation = .inline
    }

    func showController() {
        guard currentItem != nil else { return }
        presentation = .fullWindow
    }

    func bind(destinationCoordinator: PlaybackDestinationCoordinator) {
        self.destinationCoordinator = destinationCoordinator
    }

    func movePlayback(to destination: PlaybackDestination) {
        destinationCoordinator?.requestSelection(destination)
    }

    func continuePlaybackOnDevice() {
        destinationCoordinator?.continueOnDevice()
        presentation = .fullWindow
    }

    func rendererHostDidChange() {
        rendererRevision += 1
    }

    func pauseForDestinationLoss() {
        shouldAutoPlay = false
        backend?.pause()
    }

    func completeRendererHandoff(autoplay: Bool) {
        shouldAutoPlay = autoplay
        if autoplay {
            backend?.play()
        } else {
            backend?.pause()
        }
    }

    func closeAndFlush() async {
        reset()
        await progressWriteTask?.value
    }

    // MARK: - Transport control

    func play() {
        shouldAutoPlay = true
        if isPlaybackComplete {
            beginProgressWriteSession()
            isPlaybackComplete = false
            currentTime = 0
            backend?.seek(to: 0)
        }
        backend?.play()
    }

    func pause() {
        shouldAutoPlay = false
        backend?.pause()
    }

    func togglePlayback() {
        if isPlaybackComplete || !isPlaying {
            play()
        } else {
            pause()
        }
    }

    func seek(to seconds: Double) {
        guard currentItem?.type != .live else {
            reportUnsupportedControl("Seeking is unavailable for live channels.")
            return
        }
        guard seconds.isFinite else { return }
        let resolvedTime = max(0, seconds)
        handoffProgressFloor = nil
        currentTime = resolvedTime
        backend?.seek(to: resolvedTime)
    }

    // MARK: - Advanced controls

    func clearControlMessage() {
        controlMessage = nil
        canRetryEpisodeSwitch = false
        lastEpisodeSwitchAttemptID = nil
    }

    func reportUnsupportedControl(_ message: String) {
        controlMessage = message
        canRetryEpisodeSwitch = false
        lastEpisodeSwitchAttemptID = nil
    }

    func reportControlMessage(_ message: String) {
        controlMessage = message
        canRetryEpisodeSwitch = false
        lastEpisodeSwitchAttemptID = nil
    }

    func setPlaybackSpeed(_ speed: Double) {
        guard currentItem?.type != .live else {
            playbackSpeed = 1
            reportUnsupportedControl("Playback speed is unavailable for live channels.")
            return
        }
        let clamped = max(0.5, min(speed, 2.0))
        playbackSpeed = clamped
        backend?.setPlaybackSpeed(clamped)
        persistPreference("defaultSpeed", value: clamped)
    }

    func setAspectRatio(_ mode: PlayerAspectRatioMode) {
        let resolvedMode = resolveAspectRatioMode(mode)
        aspectRatioMode = resolvedMode
        backend?.setAspectRatio(resolvedMode)
        persistPreference("defaultAspectRatio", value: resolvedMode.rawValue)
    }

    func setAudioDelay(milliseconds: Int) {
        guard capabilities.supportsAudioDelay else {
            setUnsupportedFeatureMessage("Audio delay")
            return
        }

        let clamped = max(-5000, min(milliseconds, 5000))
        audioDelayMilliseconds = clamped
        backend?.setAudioDelay(milliseconds: clamped)
        persistPreference("defaultAudioDelayMs", value: clamped)
    }

    func resetAudioDelay() {
        setAudioDelay(milliseconds: 0)
    }

    func selectAudioTrack(id: String) {
        guard capabilities.supportsAudioTracks else {
            setUnsupportedFeatureMessage("Audio track selection")
            return
        }

        guard audioTracks.contains(where: { $0.id == id }) else { return }
        selectedAudioTrackID = id
        backend?.selectAudioTrack(id: id)

        if let track = audioTracks.first(where: { $0.id == id }),
           let language = track.languageCode,
           !language.isEmpty {
            persistPreference("preferredAudioLanguage", value: language)
            preferredAudioLanguageCode = language
        }
    }

    func selectSubtitleTrack(id: String) {
        guard capabilities.supportsSubtitles else {
            setUnsupportedFeatureMessage("Subtitle selection")
            return
        }

        if id != MediaTrack.subtitleOffID,
           !subtitleTracks.contains(where: { $0.id == id }) {
            return
        }

        selectedSubtitleTrackID = id
        backend?.selectSubtitleTrack(id: id)

        let enabled = id != MediaTrack.subtitleOffID
        subtitleEnabledByDefault = enabled
        persistPreference("defaultSubtitleEnabled", value: enabled)

        if let track = subtitleTracks.first(where: { $0.id == id }),
           let language = track.languageCode,
           !language.isEmpty {
            persistPreference("preferredSubtitleLanguage", value: language)
            preferredSubtitleLanguageCode = language
        }
    }

    func selectQualityVariant(id: String) {
        guard capabilities.supportsQualitySelection else {
            setUnsupportedFeatureMessage("Quality selection")
            return
        }

        guard qualityVariants.contains(where: { $0.id == id }) else { return }
        let previousID = selectedQualityVariantID
        selectedQualityVariantID = id

        do {
            try backend?.selectQualityVariant(id: id)
            controlMessage = nil
            canRetryEpisodeSwitch = false
            lastEpisodeSwitchAttemptID = nil
        } catch {
            selectedQualityVariantID = previousID
            if qualityVariants.contains(where: { $0.id == previousID }) {
                try? backend?.selectQualityVariant(id: previousID)
            }

            let previousLabel = qualityVariants.first(where: { $0.id == previousID })?.label ?? "Auto"
            controlMessage = "Could not switch quality. Reverted to \(previousLabel)."
            logger.error("Quality switch failed for id \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func jumpToChapter(id: String) {
        guard capabilities.supportsChapterMarkers else {
            setUnsupportedFeatureMessage("Chapter navigation")
            return
        }

        guard let chapter = chapterMarkers.first(where: { $0.id == id }) else { return }
        seek(to: chapter.startSeconds)
    }

    func selectOutputRoute(id: String) {
        guard capabilities.supportsOutputRouteSelection else {
            setUnsupportedFeatureMessage("Output route selection")
            return
        }

        guard outputRoutes.contains(where: { $0.id == id }) else { return }
        let previousRoutes = outputRoutes
        backend?.selectOutputRoute(id: id)
        refreshOutputRoutes()
        if outputRoutes.isEmpty {
            selectedOutputRouteID = id
            outputRoutes = previousRoutes.map { route in
                OutputRoute(id: route.id, name: route.name, isActive: route.id == id)
            }
        }
        controlMessage = nil
        canRetryEpisodeSwitch = false
        lastEpisodeSwitchAttemptID = nil
    }

    func refreshOutputRoutes() {
        guard capabilities.supportsOutputRouteSelection, let backend else {
            outputRoutes = []
            selectedOutputRouteID = nil
            return
        }

        outputRoutes = backend.availableOutputRoutes()

        if let active = outputRoutes.first(where: { $0.isActive }) {
            selectedOutputRouteID = active.id
        } else if !outputRoutes.contains(where: { $0.id == selectedOutputRouteID }) {
            selectedOutputRouteID = outputRoutes.first?.id
        }
    }

    #if os(iOS)
    func systemOutputRouteDidChange() {
        refreshOutputRoutes()
        let isAirPlayRoute = AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            $0.portType == .airPlay
        }
        guard isAirPlayRoute, activeBackendID == .vlc else { return }
        handoffToAVForAirPlayIfPossible()
    }
    #endif

    func setVolume(_ value: Double) {
        let clamped = max(0, min(value, 1))
        volume = clamped
        backend?.setVolume(clamped)
    }

    func setBrightness(_ value: Double) {
        guard capabilities.supportsBrightness else {
            setUnsupportedFeatureMessage("Brightness control")
            return
        }

        let clamped = max(0, min(value, 1))
        brightness = clamped
        backend?.setBrightness(clamped)
    }

    func setSleepTimer(_ option: SleepTimerOption) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil

        sleepTimerOption = option
        sleepTimerEndsAt = nil

        guard let seconds = option.seconds else { return }

        let fireDate = Date().addingTimeInterval(seconds)
        sleepTimerEndsAt = fireDate

        sleepTimerTask = Task { [weak self] in
            let nanoseconds = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.fireSleepTimer()
        }
    }



    // MARK: - Internals

    private func activeProvider() throws -> Provider {
        guard var provider = try database.read({ db in
            try Provider.where(\.isActive).fetchOne(db)
        }) else {
            throw MediaPlaybackSourceResolutionError.missingActiveProvider
        }
        let scheme = provider.endpoint.scheme?.lowercased()
        guard scheme == "https" || (scheme == "http" && provider.allowsInsecureHTTP) else {
            throw MediaPlaybackSourceResolutionError.insecureProviderTransport
        }
        guard !provider.credentialReference.isEmpty else {
            throw MediaPlaybackSourceResolutionError.providerCredentialsUnavailable
        }

        do {
            guard let password = try credentialStore.password(for: provider.credentialReference),
                  !password.isEmpty
            else {
                throw MediaPlaybackSourceResolutionError.providerCredentialsUnavailable
            }
            provider.password = password
            return provider
        } catch is MediaPlaybackSourceResolutionError {
            throw MediaPlaybackSourceResolutionError.providerCredentialsUnavailable
        } catch {
            logger.error("Failed to resolve provider credentials: \(error.localizedDescription, privacy: .public)")
            throw MediaPlaybackSourceResolutionError.providerCredentialsUnavailable
        }
    }

    private func playbackURL(for media: Media) throws -> URL {
        try playbackSourceResolver.playbackURL(for: media, provider: activeProvider())
    }

    private func activateBackend(for url: URL, excluding excluded: Set<PlaybackBackendID> = []) throws {
        let preferredBackendID = defaults.string(forKey: "preferredPlaybackBackend")
            .flatMap(PlaybackBackendID.init(rawValue:))
        guard let selected = backendFactory.selectBackend(
            for: url,
            excluding: excluded,
            preferred: preferredBackendID
        ) else {
            throw PlaybackRuntimeError.noRendererAvailable
        }

        eventTask?.cancel()
        eventTask = nil
        backend?.stop()

        backend = selected
        activeBackendID = selected.id
        rendererRevision += 1
        didApplyAudioPreferenceForCurrentItem = false
        didApplySubtitlePreferenceForCurrentItem = false
        bindEvents(for: selected)
    }

    private func deactivateBackend() {
        eventTask?.cancel()
        eventTask = nil

        guard backend != nil || activeBackendID != nil else { return }
        backend?.stop()
        backend = nil
        activeBackendID = nil
        rendererRevision += 1
        destinationCoordinator?.logicalPlaybackEnded()
    }

    private func bindEvents(for backend: any PlaybackBackend) {
        let backendID = backend.id
        eventTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in backend.events() {
                if Task.isCancelled { return }
                self.handle(event, from: backendID)
            }
        }
    }

    private func handle(_ event: PlaybackEvent, from backendID: PlaybackBackendID) {
        guard backendID == activeBackendID else { return }

        switch event {
        case .ready(let duration):
            isAirPlayHandoffInProgress = false
            self.duration = duration ?? self.duration
            playbackState = .ready
            isBuffering = false
            errorMessage = nil
            refreshAdvancedStateFromBackend()
            applySavedPreferencesIfPossible()
            applyPendingSeekIfNeeded()

        case .playing:
            isPlaying = true
            isBuffering = false
            playbackState = .playing

        case .paused:
            isPlaying = false
            if case .failed = playbackState {
                return
            }
            playbackState = .paused

        case .buffering(let buffering):
            isBuffering = buffering
            if buffering {
                playbackState = .buffering
            }

        case .progress(let currentTime, let duration):
            if let duration, duration.isFinite, duration > 0 {
                self.duration = duration
            }
            guard currentTime.isFinite else { return }
            let resolvedTime = max(0, currentTime)
            if let handoffProgressFloor {
                guard resolvedTime >= handoffProgressFloor else { return }
                self.handoffProgressFloor = nil
            }
            self.currentTime = resolvedTime
            persistProgressIfNeeded()

        case .advancedStateChanged:
            refreshAdvancedStateFromBackend()
            applySavedPreferencesIfPossible()
            if let avBackend = backend as? AVPlaybackBackend {
                destinationCoordinator?.avExternalPlaybackChanged(
                    isActive: avBackend.isExternalPlaybackActive
                )
            }

        case .ended:
            shouldAutoPlay = false
            isPlaying = false
            isBuffering = false
            isPlaybackComplete = true
            playbackState = .paused
            markCurrentItemCompleted()

            if sleepTimerOption == .endOfItem {
                fireSleepTimer()
            }

        case .failed(let error):
            processFailure(error, from: backendID)
        }
    }

    private func refreshAdvancedStateFromBackend() {
        guard let backend else {
            capabilities = .unsupported
            audioTracks = []
            subtitleTracks = []
            qualityVariants = [QualityVariant.auto]
            chapterMarkers = []
            outputRoutes = []
            supportedAspectRatioModes = [.fit]
            selectedOutputRouteID = nil
            return
        }

        var nextCapabilities = backend.capabilities()

        #if os(iOS)
        nextCapabilities.supportsBrightness = true
        nextCapabilities.supportsOutputRouteSelection = true
        #elseif os(tvOS)
        nextCapabilities.supportsOutputRouteSelection = true
        #endif

        capabilities = nextCapabilities
        let backendSupportedAspectRatios = backend.supportedAspectRatioModes()
        supportedAspectRatioModes = backendSupportedAspectRatios.isEmpty ? [.fit] : backendSupportedAspectRatios
        let resolvedAspectRatioMode = resolveAspectRatioMode(aspectRatioMode)
        if resolvedAspectRatioMode != aspectRatioMode {
            aspectRatioMode = resolvedAspectRatioMode
            backend.setAspectRatio(resolvedAspectRatioMode)
        }

        audioTracks = nextCapabilities.supportsAudioTracks ? backend.audioTracks() : []
        subtitleTracks = nextCapabilities.supportsSubtitles ? backend.subtitleTracks() : []

        let backendQuality = backend.qualityVariants()
        qualityVariants = backendQuality.isEmpty ? [QualityVariant.auto] : backendQuality

        chapterMarkers = nextCapabilities.supportsChapterMarkers
            ? backend.chapterMarkers().sorted { $0.startSeconds < $1.startSeconds }
            : []

        if selectedAudioTrackID == nil {
            selectedAudioTrackID = audioTracks.first(where: { $0.isDefault })?.id ?? audioTracks.first?.id
        }

        if !subtitleTracks.contains(where: { $0.id == selectedSubtitleTrackID }) {
            selectedSubtitleTrackID = MediaTrack.subtitleOffID
        }

        if !qualityVariants.contains(where: { $0.id == selectedQualityVariantID }) {
            selectedQualityVariantID = qualityVariants.first(where: { $0.isAuto })?.id ?? qualityVariants[0].id
        }

        if nextCapabilities.supportsOutputRouteSelection {
            refreshOutputRoutes()
        } else {
            outputRoutes = []
            selectedOutputRouteID = nil
        }
    }

    private func applySavedPreferencesIfPossible() {
        let effectiveSpeed = currentItem?.type == .live ? 1 : playbackSpeed
        backend?.setPlaybackSpeed(effectiveSpeed)
        backend?.setAspectRatio(resolveAspectRatioMode(aspectRatioMode))
        backend?.setAudioDelay(milliseconds: audioDelayMilliseconds)
        backend?.setVolume(volume)
        if capabilities.supportsBrightness {
            backend?.setBrightness(brightness)
        }

        if !didApplyAudioPreferenceForCurrentItem {
            if let preferredAudioLanguageCode {
                if let match = preferredTrack(in: audioTracks, language: preferredAudioLanguageCode) {
                    selectedAudioTrackID = match.id
                    backend?.selectAudioTrack(id: match.id)
                    didApplyAudioPreferenceForCurrentItem = true
                }
            } else {
                didApplyAudioPreferenceForCurrentItem = true
            }
        }

        if !didApplySubtitlePreferenceForCurrentItem {
            if subtitleEnabledByDefault {
                if let preferredSubtitleLanguageCode {
                    if let match = preferredTrack(in: subtitleTracks, language: preferredSubtitleLanguageCode) {
                        selectedSubtitleTrackID = match.id
                        backend?.selectSubtitleTrack(id: match.id)
                        didApplySubtitlePreferenceForCurrentItem = true
                    }
                } else if let fallback = subtitleTracks.first(where: \.isDefault) ?? subtitleTracks.first {
                    selectedSubtitleTrackID = fallback.id
                    backend?.selectSubtitleTrack(id: fallback.id)
                    didApplySubtitlePreferenceForCurrentItem = true
                }
            } else if !subtitleTracks.isEmpty {
                selectedSubtitleTrackID = MediaTrack.subtitleOffID
                backend?.selectSubtitleTrack(id: MediaTrack.subtitleOffID)
                didApplySubtitlePreferenceForCurrentItem = true
            }
        }
    }

    private func preferredTrack(in tracks: [MediaTrack], language: String) -> MediaTrack? {
        guard let preferred = normalizedLanguageIdentifier(language) else { return nil }
        if let exact = tracks.first(where: {
            normalizedLanguageIdentifier($0.languageCode) == preferred
        }) {
            return exact
        }

        let preferredParts = preferred.split(separator: "-", omittingEmptySubsequences: true)
        guard preferredParts.count == 1, let primaryLanguage = preferredParts.first else {
            return nil
        }
        return tracks.first {
            normalizedLanguageIdentifier($0.languageCode)?
                .split(separator: "-", omittingEmptySubsequences: true)
                .first == primaryLanguage
        }
    }

    private func normalizedLanguageIdentifier(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func unavailableReason(for feature: PlayerFeature) -> String? {
        switch feature {
        case .audioTracks:
            guard !capabilities.supportsAudioTracks else { return nil }
            return "Audio: the current source does not expose alternate audio renditions, so the player cannot offer language or commentary switching."

        case .subtitles:
            guard !capabilities.supportsSubtitles else { return nil }
            return "Subtitles: no selectable subtitle tracks are advertised by the current source."

        case .quality:
            guard !capabilities.supportsQualitySelection else { return nil }

//            if currentPlaybackSource?.origin == .offline {
//                return "Quality: offline downloads are single local files, so adaptive quality variants are no longer available."
//            }

            return "Quality: the current stream/backend does not expose multiple selectable video variants."

        case .chapters:
            guard !capabilities.supportsChapterMarkers else { return nil }
            return "Chapters: no chapter metadata is present in the current asset."

        case .outputRoute:
            guard !capabilities.supportsOutputRouteSelection else { return nil }
            #if os(macOS)
            return "Output device: the current macOS player path does not implement programmatic route switching. Device changes still have to happen through the system."
            #else
            return "Output device: route selection is not available from the current backend."
            #endif

        case .audioDelay:
            guard !capabilities.supportsAudioDelay else { return nil }
            if activeBackendID == .av {
                return "Audio delay: AVPlayer has no public API for per-item audio offset adjustment, so this control is only available through the VLC backend."
            }
            return "Audio delay: the current backend does not expose adjustable audio offset control."

        case .brightness:
            guard !capabilities.supportsBrightness else { return nil }
            #if os(macOS)
            return "Brightness: macOS does not provide safe per-window playback brightness controls like iOS/tvOS, so changing this from the app is not currently supported."
            #else
            return "Brightness: the current backend does not expose brightness control."
            #endif
        }
    }

    private func loadSavedPreferencesForCurrentProfile() {
        if let storedSpeed = defaults.object(forKey: "defaultSpeed") as? Double,
           storedSpeed.isFinite,
           storedSpeed > 0 {
            playbackSpeed = storedSpeed
        } else {
            playbackSpeed = 1
        }

        if let rawAspect = defaults.string(forKey: "defaultAspectRatio"),
           let mode = PlayerAspectRatioMode(rawValue: rawAspect) {
            aspectRatioMode = mode
        } else {
            aspectRatioMode = .fit
        }

        if let storedDelay = defaults.object(forKey: "defaultAudioDelayMs") as? Int {
            audioDelayMilliseconds = storedDelay
        } else {
            audioDelayMilliseconds = 0
        }

        preferredAudioLanguageCode = defaults.string(forKey: "preferredAudioLanguage")
        preferredSubtitleLanguageCode = defaults.string(forKey: "preferredSubtitleLanguage")

        if defaults.object(forKey: "defaultSubtitleEnabled") != nil {
            subtitleEnabledByDefault = defaults.bool(forKey: "defaultSubtitleEnabled")
        } else {
            subtitleEnabledByDefault = false
        }
    }

    private func persistPreference(_ key: String, value: Any) {
        defaults.set(value, forKey: key)
    }

    private func resolveAspectRatioMode(_ requested: PlayerAspectRatioMode) -> PlayerAspectRatioMode {
        if supportedAspectRatioModes.contains(requested) {
            return requested
        }

        if supportedAspectRatioModes.contains(.fit) {
            return .fit
        }

        return supportedAspectRatioModes.first ?? .fit
    }

    private var currentStreamDescriptor: String {
        guard let currentItem else { return "the current stream" }

        if currentItem.type == .live {
            return "this live channel"
        }

        if let ext = currentItem.containerExtension?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ext.isEmpty {
            return "a fixed \(ext.uppercased()) stream"
        }

        return currentItem.type == .episode ? "this episode stream" : "this movie stream"
    }

    private func setUnsupportedFeatureMessage(_ feature: String) {
        controlMessage = "\(feature) is not supported by the current stream/backend."
        canRetryEpisodeSwitch = false
        lastEpisodeSwitchAttemptID = nil
    }

    private func fireSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil

        sleepTimerOption = .off
        sleepTimerEndsAt = nil

        pause()
        presentation = .inline
        controlMessage = "Sleep timer finished. Playback paused."
    }

    private func applyPendingSeekIfNeeded() {
        if let handoffTime = pendingHandoffTime {
            pendingHandoffTime = nil
            currentTime = handoffTime
            handoffProgressFloor = handoffTime
            backend?.seek(to: handoffTime)
            return
        }

        guard let resumeTime = pendingResumeTime else { return }
        pendingResumeTime = nil

        guard WatchActivityStore.isResumeEligible(
            currentTime: resumeTime,
            duration: duration,
            completed: false
        ) else {
            return
        }

        currentTime = resumeTime
        backend?.seek(to: resumeTime)
        controlMessage = "Resumed \(currentStreamDescriptor) at \(Self.formatTime(resumeTime))."
    }

    private func processFailure(_ error: Error, from backendID: PlaybackBackendID) {
        logger.error("Playback backend \(backendID.rawValue, privacy: .public) failed category=\(String(describing: type(of: error)), privacy: .public)")

        #if os(iOS)
        if backendID == .av, isAirPlayHandoffInProgress {
            rollbackAirPlayHandoff()
            return
        }
        #endif

        guard backendID == .vlc,
              !didFallbackForCurrentItem,
              let currentItem
        else {
            processTerminalFailure(error)
            return
        }

        didFallbackForCurrentItem = true
        let handoffTime = currentTime.isFinite ? max(0, currentTime) : 0
        let continuePlaying = shouldAutoPlay
        pendingHandoffTime = handoffTime > 0 ? handoffTime : nil
        handoffProgressFloor = handoffTime > 0 ? handoffTime : nil
        logger.info("Attempting automatic playback fallback to AV backend.")

        do {
            let url = try currentPlaybackURL ?? playbackURL(for: currentItem)
            try activateBackend(for: url, excluding: [.vlc])
            try backend?.load(url: url, autoplay: continuePlaying)
            isPlaying = false
            playbackState = .loading
            errorMessage = nil
        } catch {
            processTerminalFailure(error)
        }
    }


    #if os(iOS)
    private func handoffToAVForAirPlayIfPossible() {
        guard let url = currentPlaybackURL,
              backendFactory.selectBackend(for: url, excluding: [.vlc], preferred: .av) != nil
        else {
            reportControlMessage("This stream is not compatible with AirPlay video. Playback remains on this device.")
            return
        }

        let handoffTime = currentTime.isFinite ? max(0, currentTime) : 0
        let continuePlaying = shouldAutoPlay
        pendingHandoffTime = handoffTime > 0 ? handoffTime : nil
        handoffProgressFloor = handoffTime > 0 ? handoffTime : nil

        do {
            isAirPlayHandoffInProgress = true
            try activateBackend(for: url, excluding: [.vlc])
            try backend?.load(url: url, autoplay: continuePlaying)
            isPlaying = false
            playbackState = .loading
            errorMessage = nil
            reportControlMessage("Connecting AirPlay video…")
        } catch {
            isAirPlayHandoffInProgress = false
            do {
                try activateBackend(for: url, excluding: [.av])
                try backend?.load(url: url, autoplay: continuePlaying)
                reportControlMessage("AirPlay video is unavailable for this stream. Playback remains on this device.")
            } catch {
                processTerminalFailure(error)
            }
        }
    }

    private func rollbackAirPlayHandoff() {
        isAirPlayHandoffInProgress = false
        didFallbackForCurrentItem = true
        guard let url = currentPlaybackURL else {
            processTerminalFailure(PlaybackRuntimeError.missingPlaybackURL)
            return
        }

        let continuePlaying = shouldAutoPlay
        pendingHandoffTime = currentTime > 0 ? currentTime : nil
        do {
            try activateBackend(for: url, excluding: [.av])
            try backend?.load(url: url, autoplay: continuePlaying)
            playbackState = .loading
            errorMessage = nil
            reportControlMessage("AirPlay video could not start. Playback returned to this device.")
        } catch {
            processTerminalFailure(error)
        }
    }
    #endif

    private func processTerminalFailure(_ error: Error) {
        deactivateBackend()
        isPlaying = false
        isBuffering = false
        let message: String
        switch error {
        case let error as MediaPlaybackSourceResolutionError:
            message = error.localizedDescription
        case let error as PlaybackRuntimeError:
            message = error.localizedDescription
        default:
            message = "Playback failed for the current stream."
        }
        errorMessage = message
        playbackState = .failed(message)
        logger.error("Terminal playback failure category=\(String(describing: type(of: error)), privacy: .public)")
    }

    private func beginProgressWriteSession() {
        let now = Date()
        progressWriteSessionStartedAt = now > progressWriteSessionStartedAt
            ? now
            : progressWriteSessionStartedAt.addingTimeInterval(0.000_001)
        progressWriteGeneration = 0

        if let currentItem, let providerID = currentProviderID {
            let key = progressKey(for: currentItem, providerID: providerID)
            lastScheduledProgressByVideoKey[key] = nil
            lastPersistedProgressByVideoKey[key] = nil
        }
    }

    private func persistProgressIfNeeded(force: Bool = false) {
        guard let currentItem, let providerID = currentProviderID else { return }
        guard currentItem.type == .movie || currentItem.type == .episode else { return }
        guard currentTime.isFinite else { return }

        let currentTime = max(0, self.currentTime)
        guard currentTime > 0 || isPlaybackComplete else { return }
        let duration = self.duration
        let fraction: Double = if let duration, duration > 0 {
            min(max(currentTime / duration, 0), 1)
        } else {
            0
        }
        let key = progressKey(for: currentItem, providerID: providerID)
        let latest = lastScheduledProgressByVideoKey[key] ?? lastPersistedProgressByVideoKey[key]

        if !force,
           let latest,
           abs(currentTime - latest.time) < 10,
           abs(fraction - latest.fraction) < 0.05 {
            return
        }

        enqueueProgressWrite(
            for: currentItem,
            providerID: providerID,
            key: key,
            currentTime: currentTime,
            duration: duration,
            completed: isPlaybackComplete,
            fraction: fraction
        )
    }

    private func markCurrentItemCompleted() {
        guard let currentItem, let providerID = currentProviderID else { return }
        guard currentItem.type == .movie || currentItem.type == .episode else { return }

        let completedTime = max(currentTime, duration ?? currentTime)
        currentTime = completedTime
        let fraction = duration.map { $0 > 0 ? min(max(completedTime / $0, 0), 1) : 0 } ?? 0
        enqueueProgressWrite(
            for: currentItem,
            providerID: providerID,
            key: progressKey(for: currentItem, providerID: providerID),
            currentTime: completedTime,
            duration: duration,
            completed: true,
            fraction: fraction
        )
    }

    private func enqueueProgressWrite(
        for currentItem: Media,
        providerID: Provider.ID,
        key: String,
        currentTime: Double,
        duration: Double?,
        completed: Bool,
        fraction: Double
    ) {
        if progressWriteSessionStartedAt == .distantPast {
            beginProgressWriteSession()
        }
        progressWriteGeneration &+= 1
        let sessionStartedAt = progressWriteSessionStartedAt
        let stamp = WatchActivityStore.WriteStamp(
            sessionStartedAt: sessionStartedAt,
            generation: progressWriteGeneration
        )
        let snapshot = (time: currentTime, fraction: fraction)
        lastScheduledProgressByVideoKey[key] = snapshot
        let previousWrite = progressWriteTask
        let database = self.database

        progressWriteTask = Task.detached(priority: .utility) { [weak self] in
            if let previousWrite {
                await previousWrite.value
            }
            let committed = await WatchActivityStore.recordProgress(
                for: currentItem,
                providerID: providerID,
                currentTime: currentTime,
                duration: duration,
                completed: completed,
                writeStamp: stamp,
                database: database
            )
            await MainActor.run { [weak self] in
                guard let self, self.progressWriteSessionStartedAt == sessionStartedAt else { return }
                if committed {
                    self.lastPersistedProgressByVideoKey[key] = snapshot
                } else if let scheduled = self.lastScheduledProgressByVideoKey[key],
                          scheduled.time == snapshot.time,
                          scheduled.fraction == snapshot.fraction {
                    self.lastScheduledProgressByVideoKey[key] = nil
                }
            }
        }
    }

    private func progressKey(for media: Media, providerID: Provider.ID) -> String {
        "\(providerID):\(media.type.rawValue):\(media.sourceID)"
    }

    private static func formatTime(_ rawSeconds: Double) -> String {
        guard rawSeconds.isFinite else { return "00:00" }
        let totalSeconds = max(0, Int(rawSeconds.rounded()))
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
