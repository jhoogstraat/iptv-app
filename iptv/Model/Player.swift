/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model object that manages stream playback and backend fallback.
*/

import AVFoundation
import Foundation
import Observation
import OSLog

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
    private(set) var currentItem: Video?
    private(set) var currentURL: URL?
    private(set) var currentPlaybackSource: PlaybackSource?
    private(set) var currentTime: Double = 0
    private(set) var duration: Double?
    private(set) var errorMessage: String?
    private(set) var activeBackendID: PlaybackBackendID?
    private(set) var rendererRevision = 0
    private(set) var shouldAutoPlay = true

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
    private(set) var audioDelayMilliseconds = 0
    private(set) var volume: Double = 1
    private(set) var brightness: Double = 0.5

    private(set) var sleepTimerOption: SleepTimerOption = .off
    private(set) var sleepTimerEndsAt: Date?

    private(set) var controlMessage: String?
    private(set) var canRetryEpisodeSwitch = false

    private(set) var episodeOptions: [Video] = []

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

    private let backendFactory: PlaybackBackendFactory
    private let watchActivityStore: any WatchActivityStoring
    private let providerFingerprintProvider: @MainActor () -> String?
    private let defaults: UserDefaults
    private var backend: (any PlaybackBackend)?
    private var eventTask: Task<Void, Never>?
    private var sleepTimerTask: Task<Void, Never>?
    private var didFallbackForCurrentItem = false
    private var lastPersistedProgressByVideoKey: [String: (time: Double, fraction: Double)] = [:]
    private var preferredAudioLanguageCode: String?
    private var preferredSubtitleLanguageCode: String?
    private var subtitleEnabledByDefault = false
    private var didApplyTrackPreferencesForCurrentItem = false
    private var episodeSourceResolver: ((Video) async throws -> PlaybackSource)?
    private var lastEpisodeSwitchAttemptID: Int?

    init(
        backendFactory: PlaybackBackendFactory? = nil,
        watchActivityStore: (any WatchActivityStoring)? = nil,
        providerFingerprintProvider: @escaping @MainActor () -> String? = { nil },
        defaults: UserDefaults = .standard
    ) {
        self.backendFactory = backendFactory ?? PlaybackBackendFactory()
        self.watchActivityStore = watchActivityStore ?? DiskWatchActivityStore.shared
        self.providerFingerprintProvider = providerFingerprintProvider
        self.defaults = defaults
    }

    var vlcRenderer: VLCPlayerReference? {
        (backend as? VLCPlaybackBackend)?.player
    }

    var avRenderer: AVPlayer? {
        (backend as? AVPlaybackBackend)?.player
    }

    /// Loads a stream for playback in the requested presentation.
    func load(_ video: Video, _ source: PlaybackSource, presentation: Presentation, autoplay: Bool = true) {
        currentItem = video
        currentURL = source.url
        currentPlaybackSource = source
        shouldAutoPlay = autoplay
        didFallbackForCurrentItem = false
        isPlaybackComplete = false
        errorMessage = nil
        controlMessage = nil
        canRetryEpisodeSwitch = false
        lastEpisodeSwitchAttemptID = nil
        currentTime = 0
        duration = nil
        playbackState = .loading
        self.presentation = presentation
        didApplyTrackPreferencesForCurrentItem = false

        let key = makePersistenceKey(for: video)
        lastPersistedProgressByVideoKey[key] = nil

        if episodeOptions.isEmpty || !episodeOptions.contains(where: { $0.id == video.id }) {
            episodeOptions = [video]
        }

        loadSavedPreferencesForCurrentProfile()

        do {
            try activateBackend(for: video, url: source.url)
            refreshAdvancedStateFromBackend()
            applySavedPreferencesIfPossible()
            try backend?.load(url: source.url, autoplay: autoplay)
            logger.info("Playback started with backend \(self.activeBackendID?.rawValue ?? "unknown", privacy: .public)")
        } catch {
            processTerminalFailure(error)
        }
    }

    /// Loads a stream URL directly for playback in the requested presentation.
    func load(_ video: Video, _ url: URL, presentation: Presentation, autoplay: Bool = true) {
        load(video, .streaming(url), presentation: presentation, autoplay: autoplay)
    }

    /// Clears any loaded media and resets the player model to its default state.
    func reset() {
        eventTask?.cancel()
        eventTask = nil

        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerOption = .off
        sleepTimerEndsAt = nil

        backend?.stop()
        backend = nil
        activeBackendID = nil
        rendererRevision += 1

        currentItem = nil
        currentURL = nil
        currentPlaybackSource = nil
        shouldAutoPlay = true
        didFallbackForCurrentItem = false
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
        audioDelayMilliseconds = 0
        volume = 1
        brightness = 0.5

        episodeOptions = []
        episodeSourceResolver = nil

        didApplyTrackPreferencesForCurrentItem = false
        lastPersistedProgressByVideoKey.removeAll()
    }

    func close() {
        reset()
    }

    // MARK: - Transport control

    func play() {
        backend?.play()
    }

    func pause() {
        backend?.pause()
    }

    func togglePlayback() {
        backend?.togglePlayback()
    }

    func seek(to seconds: Double) {
        backend?.seek(to: seconds)
    }

    // MARK: - Advanced controls

    func clearControlMessage() {
        controlMessage = nil
        canRetryEpisodeSwitch = false
        lastEpisodeSwitchAttemptID = nil
    }

    func setPlaybackSpeed(_ speed: Double) {
        let clamped = max(0.5, min(speed, 2.0))
        playbackSpeed = clamped
        backend?.setPlaybackSpeed(clamped)
        persistPreference("defaultSpeed", value: clamped)
    }

    func setAspectRatio(_ mode: PlayerAspectRatioMode) {
        aspectRatioMode = mode
        backend?.setAspectRatio(mode)
        persistPreference("defaultAspectRatio", value: mode.rawValue)
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

    func configureEpisodeSwitcher(
        episodes: [Video],
        resolver: @escaping (Video) async throws -> PlaybackSource
    ) {
        episodeOptions = episodes
        episodeSourceResolver = resolver
    }

    func quickSwitchEpisode(id: Int) {
        guard let target = episodeOptions.first(where: { $0.id == id }) else { return }
        guard let resolver = episodeSourceResolver else {
            setUnsupportedFeatureMessage("Episode quick switch")
            return
        }

        lastEpisodeSwitchAttemptID = id
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let source = try await resolver(target)
                self.canRetryEpisodeSwitch = false
                self.controlMessage = nil
                self.load(target, source, presentation: self.presentation, autoplay: true)
            } catch {
                self.controlMessage = "Could not switch episode. Try again."
                self.canRetryEpisodeSwitch = true
                logger.error("Episode quick switch failed for id \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func retryEpisodeSwitch() {
        guard canRetryEpisodeSwitch, let id = lastEpisodeSwitchAttemptID else { return }
        quickSwitchEpisode(id: id)
    }

    // MARK: - Internals

    private func activateBackend(for video: Video, url: URL, excluding excluded: Set<PlaybackBackendID> = []) throws {
        guard let selected = backendFactory.selectBackend(
            for: url,
            contentType: video.contentType,
            containerExtension: video.containerExtension,
            excluding: excluded
        ) else {
            throw PlaybackRuntimeError.noRendererAvailable
        }

        eventTask?.cancel()
        eventTask = nil
        backend?.stop()

        backend = selected
        activeBackendID = selected.id
        rendererRevision += 1
        bindEvents(for: selected)
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
        switch event {
        case .ready(let duration):
            self.duration = duration ?? self.duration
            playbackState = .ready
            isBuffering = false
            errorMessage = nil
            refreshAdvancedStateFromBackend()
            applySavedPreferencesIfPossible()

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
            self.currentTime = max(0, currentTime)
            if let duration, duration > 0 {
                self.duration = duration
            }
            persistProgressIfNeeded()

        case .advancedStateChanged:
            refreshAdvancedStateFromBackend()
            applySavedPreferencesIfPossible()

        case .ended:
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
            selectedOutputRouteID = nil
            return
        }

        var nextCapabilities = backend.capabilities()

        #if os(iOS) || os(tvOS)
        nextCapabilities.supportsBrightness = true
        nextCapabilities.supportsOutputRouteSelection = true
        #endif

        capabilities = nextCapabilities

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
        backend?.setPlaybackSpeed(playbackSpeed)
        backend?.setAspectRatio(aspectRatioMode)
        backend?.setAudioDelay(milliseconds: audioDelayMilliseconds)

        guard !didApplyTrackPreferencesForCurrentItem else { return }
        didApplyTrackPreferencesForCurrentItem = true

        if let preferredAudioLanguageCode,
           let match = audioTracks.first(where: { language($0.languageCode, matches: preferredAudioLanguageCode) }) {
            selectedAudioTrackID = match.id
            backend?.selectAudioTrack(id: match.id)
        }

        if subtitleEnabledByDefault {
            if let preferredSubtitleLanguageCode,
               let match = subtitleTracks.first(where: { language($0.languageCode, matches: preferredSubtitleLanguageCode) }) {
                selectedSubtitleTrackID = match.id
                backend?.selectSubtitleTrack(id: match.id)
            } else if let fallback = subtitleTracks.first {
                selectedSubtitleTrackID = fallback.id
                backend?.selectSubtitleTrack(id: fallback.id)
            }
        } else {
            selectedSubtitleTrackID = MediaTrack.subtitleOffID
            backend?.selectSubtitleTrack(id: MediaTrack.subtitleOffID)
        }
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

            if currentPlaybackSource?.origin == .offline {
                return "Quality: offline downloads are single local files, so adaptive quality variants are no longer available."
            }

            if activeBackendID == .av, !isAdaptiveStream {
                let descriptor = currentStreamDescriptor
                return "Quality: AVPlayer can only switch variants on adaptive manifests such as HLS. The current source is \(descriptor), so there is only one playable rendition."
            }

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
        let keyPrefix = profilePreferencePrefix()

        if let storedSpeed = defaults.object(forKey: "\(keyPrefix).defaultSpeed") as? Double,
           storedSpeed.isFinite,
           storedSpeed > 0 {
            playbackSpeed = storedSpeed
        } else {
            playbackSpeed = 1
        }

        if let rawAspect = defaults.string(forKey: "\(keyPrefix).defaultAspectRatio"),
           let mode = PlayerAspectRatioMode(rawValue: rawAspect) {
            aspectRatioMode = mode
        } else {
            aspectRatioMode = .fit
        }

        if let storedDelay = defaults.object(forKey: "\(keyPrefix).defaultAudioDelayMs") as? Int {
            audioDelayMilliseconds = storedDelay
        } else {
            audioDelayMilliseconds = 0
        }

        preferredAudioLanguageCode = defaults.string(forKey: "\(keyPrefix).preferredAudioLanguage")
        preferredSubtitleLanguageCode = defaults.string(forKey: "\(keyPrefix).preferredSubtitleLanguage")

        if defaults.object(forKey: "\(keyPrefix).defaultSubtitleEnabled") != nil {
            subtitleEnabledByDefault = defaults.bool(forKey: "\(keyPrefix).defaultSubtitleEnabled")
        } else {
            subtitleEnabledByDefault = false
        }
    }

    private func persistPreference(_ key: String, value: Any) {
        defaults.set(value, forKey: "\(profilePreferencePrefix()).\(key)")
    }

    private func profilePreferencePrefix() -> String {
        let profile = providerFingerprintProvider() ?? "default"
        return "player.preferences.\(profile)"
    }

    private func language(_ lhs: String?, matches rhs: String) -> Bool {
        guard let lhs, !lhs.isEmpty else { return false }
        let normalizedLHS = lhs.lowercased()
        let normalizedRHS = rhs.lowercased()

        if normalizedLHS == normalizedRHS {
            return true
        }

        let lhsPrimary = normalizedLHS.split(separator: "-").first.map(String.init)
        let rhsPrimary = normalizedRHS.split(separator: "-").first.map(String.init)
        return lhsPrimary == rhsPrimary
    }

    private var isAdaptiveStream: Bool {
        let itemExtension = currentItem?.containerExtension.lowercased()
        let urlExtension = currentURL?.pathExtension.lowercased()
        return itemExtension == "m3u8" || urlExtension == "m3u8"
    }

    private var currentStreamDescriptor: String {
        if currentPlaybackSource?.origin == .offline {
            return "an offline file"
        }

        if let ext = currentItem?.containerExtension.lowercased(), !ext.isEmpty {
            return "a fixed \(ext.uppercased()) stream"
        }

        if let ext = currentURL?.pathExtension.lowercased(), !ext.isEmpty {
            return "a fixed \(ext.uppercased()) stream"
        }

        return "a fixed direct stream"
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

    private func processFailure(_ error: Error, from backendID: PlaybackBackendID) {
        logger.error("Playback backend \(backendID.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")

        guard backendID == .vlc,
              !didFallbackForCurrentItem,
              let currentItem,
              let currentPlaybackSource
        else {
            processTerminalFailure(error)
            return
        }

        didFallbackForCurrentItem = true
        logger.info("Attempting automatic playback fallback to AV backend.")

        do {
            try activateBackend(for: currentItem, url: currentPlaybackSource.url, excluding: [.vlc])
            refreshAdvancedStateFromBackend()
            applySavedPreferencesIfPossible()
            try backend?.load(url: currentPlaybackSource.url, autoplay: shouldAutoPlay)
            playbackState = .loading
            errorMessage = nil
        } catch {
            processTerminalFailure(error)
        }
    }

    private func processTerminalFailure(_ error: Error) {
        isPlaying = false
        isBuffering = false
        let message = error.localizedDescription
        errorMessage = message
        playbackState = .failed(message)
        logger.error("Terminal playback failure: \(message, privacy: .public)")
    }

    private func persistProgressIfNeeded() {
        guard let currentItem else { return }
        guard let providerFingerprint = providerFingerprintProvider() else { return }

        let key = makePersistenceKey(for: currentItem)
        let fraction = progressFraction

        if let persisted = lastPersistedProgressByVideoKey[key],
           abs(currentTime - persisted.time) < 10,
           abs(fraction - persisted.fraction) < 0.05 {
            return
        }

        lastPersistedProgressByVideoKey[key] = (currentTime, fraction)

        let input = WatchActivityInput(
            videoID: currentItem.id,
            contentType: currentItem.contentType,
            title: currentItem.name,
            coverImageURL: currentItem.coverImageURL,
            containerExtension: currentItem.containerExtension,
            rating: currentItem.rating
        )

        let currentTime = self.currentTime
        let duration = self.duration
        Task(priority: .utility) {
            await watchActivityStore.recordProgress(
                input: input,
                providerFingerprint: providerFingerprint,
                currentTime: currentTime,
                duration: duration
            )
        }
    }

    private func markCurrentItemCompleted() {
        guard let currentItem else { return }
        guard let providerFingerprint = providerFingerprintProvider() else { return }

        let input = WatchActivityInput(
            videoID: currentItem.id,
            contentType: currentItem.contentType,
            title: currentItem.name,
            coverImageURL: currentItem.coverImageURL,
            containerExtension: currentItem.containerExtension,
            rating: currentItem.rating
        )

        Task(priority: .utility) {
            await watchActivityStore.markCompleted(input: input, providerFingerprint: providerFingerprint)
        }
    }

    private func makePersistenceKey(for video: Video) -> String {
        "\(video.contentType):\(video.id)"
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
