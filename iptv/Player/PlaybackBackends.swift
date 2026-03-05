//
//  PlaybackBackends.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import AVFoundation
import Foundation
import OSLog

#if os(iOS) || os(tvOS)
import UIKit
#endif

#if canImport(VLCKit)
import VLCKit
#endif

private enum SystemOutputRouteID {
    static let automatic = "__route_automatic__"
    static let speaker = "__route_speaker__"
}

@MainActor
private struct SystemOutputRouteController {
    #if os(iOS) || os(tvOS)
    private let session = AVAudioSession.sharedInstance()

    func availableRoutes() -> [OutputRoute] {
        let outputs = session.currentRoute.outputs
        var routes = outputs.map { output in
            OutputRoute(
                id: routeID(for: output),
                name: output.portName,
                isActive: true
            )
        }

        #if os(iOS)
        let speakerActive = outputs.contains(where: { $0.portType == .builtInSpeaker })
        routes.insert(
            OutputRoute(
                id: SystemOutputRouteID.automatic,
                name: "System Default",
                isActive: !speakerActive
            ),
            at: 0
        )
        routes.insert(
            OutputRoute(
                id: SystemOutputRouteID.speaker,
                name: "iPhone Speaker",
                isActive: speakerActive
            ),
            at: 1
        )
        #endif

        var seen = Set<String>()
        routes = routes.filter { route in
            seen.insert(route.id).inserted
        }

        if routes.isEmpty {
            routes = [
                OutputRoute(
                    id: SystemOutputRouteID.automatic,
                    name: "System Default",
                    isActive: true
                )
            ]
        }

        return routes
    }

    func selectRoute(id: String) {
        #if os(iOS)
        do {
            switch id {
            case SystemOutputRouteID.automatic:
                try session.overrideOutputAudioPort(.none)
            case SystemOutputRouteID.speaker:
                try session.overrideOutputAudioPort(.speaker)
            default:
                // External routes are selected by the system route picker UI.
                break
            }
        } catch {
            logger.error("Failed to set output route \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        #else
        _ = id
        #endif
    }

    private func routeID(for output: AVAudioSessionPortDescription) -> String {
        if !output.uid.isEmpty {
            return "avroute:\(output.uid)"
        }
        return "avroute:\(output.portType.rawValue):\(output.portName.lowercased())"
    }
    #else
    func availableRoutes() -> [OutputRoute] { [] }
    func selectRoute(id: String) { _ = id }
    #endif
}

enum PlaybackRuntimeError: LocalizedError {
    case backendFailure(String)
    case noRendererAvailable

    var errorDescription: String? {
        switch self {
        case .backendFailure(let message):
            return message
        case .noRendererAvailable:
            return "No supported playback backend is available for this stream."
        }
    }
}


#if canImport(VLCKit)
@MainActor
final class VLCPlaybackBackend: NSObject, PlaybackBackend {
    let id: PlaybackBackendID = .vlc
    let player: VLCPlayerReference = VLCMediaPlayer()

    var isAvailable: Bool { true }

    private let stream: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private var progressTask: Task<Void, Never>?
    private let outputRouteController = SystemOutputRouteController()
    private var automaticQualityTrackID: String?

    override init() {
        var continuation: AsyncStream<PlaybackEvent>.Continuation?
        self.stream = AsyncStream<PlaybackEvent> { continuation = $0 }
        self.continuation = continuation!
        super.init()
        player.delegate = self
    }

    func canPlay(url: URL, contentType: String, containerExtension: String?) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        return ["http", "https", "rtsp", "file"].contains(scheme) || !scheme.isEmpty
    }

    func load(url: URL, autoplay: Bool) throws {
        automaticQualityTrackID = nil
        player.media = VLCMedia(url: url)
        continuation.yield(.ready(duration: mediaDuration()))
        if autoplay {
            play()
        }
        startProgressTimer()
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayback() {
        player.isPlaying ? player.pause() : player.play()
    }

    func stop() {
        stopProgressTimer()
        player.stop()
    }

    func seek(to seconds: Double) {
        let milliseconds = Int32(max(0, seconds) * 1000.0)
        player.time = VLCTime(int: milliseconds)
    }

    func events() -> AsyncStream<PlaybackEvent> {
        stream
    }

    func capabilities() -> PlaybackCapabilities {
        let audio = audioTracks()
        let subtitles = subtitleTracks()
        let quality = qualityVariants()
        let chapters = chapterMarkers()

        return PlaybackCapabilities(
            supportsAudioTracks: !audio.isEmpty,
            supportsSubtitles: !subtitles.isEmpty,
            supportsQualitySelection: quality.contains(where: { !$0.isAuto }),
            supportsChapterMarkers: !chapters.isEmpty,
            supportsOutputRouteSelection: supportsSystemRoutePicker,
            supportsAudioDelay: true,
            supportsBrightness: supportsBrightnessControl
        )
    }

    func audioTracks() -> [MediaTrack] {
        player.audioTracks.map { track in
            MediaTrack(
                id: mediaTrackID(for: track, kind: .audio),
                kind: .audio,
                languageCode: normalizedLanguageCode(track.language),
                label: mediaTrackLabel(for: track, fallbackPrefix: "Audio"),
                isDefault: track.isSelected,
                isForced: false
            )
        }
    }

    func subtitleTracks() -> [MediaTrack] {
        player.textTracks.map { track in
            MediaTrack(
                id: mediaTrackID(for: track, kind: .subtitle),
                kind: .subtitle,
                languageCode: normalizedLanguageCode(track.language),
                label: mediaTrackLabel(for: track, fallbackPrefix: "Subtitle"),
                isDefault: track.isSelected,
                isForced: false
            )
        }
    }

    func qualityVariants() -> [QualityVariant] {
        cacheAutomaticQualityTrackIfNeeded()

        let manualVariants = player.videoTracks.enumerated().map { index, track in
            let video = track.video
            let width = video?.width ?? 0
            let height = video?.height ?? 0
            let resolution: String? = (width > 0 && height > 0) ? "\(width)x\(height)" : nil

            let frameRate: Double? = {
                let numerator = video?.frameRate ?? 0
                let denominator = max(video?.frameRateDenominator ?? 1, 1)
                guard numerator > 0 else { return nil }
                return Double(numerator) / Double(denominator)
            }()

            let bitrate = track.bitrate > 0 ? Int(track.bitrate) : nil
            return QualityVariant(
                id: qualityVariantID(for: track),
                label: mediaTrackLabel(for: track, fallbackPrefix: "Track \(index + 1)"),
                bitrate: bitrate,
                resolution: resolution,
                frameRate: frameRate,
                isAuto: false
            )
        }

        guard !manualVariants.isEmpty else { return [] }
        return [QualityVariant.auto] + manualVariants
    }

    func chapterMarkers() -> [ChapterMarker] {
        let titles = player.titleDescriptions as NSArray
        guard titles.count > 0 else { return [] }

        let includeTitleLabel = titles.count > 1
        var markers: [ChapterMarker] = []

        for case let title as VLCMediaPlayer.TitleDescription in titles {
            let chapterDescriptions = title.chapterDescriptions as NSArray
            for case let chapter as VLCMediaPlayer.ChapterDescription in chapterDescriptions {
                let startMilliseconds = chapter.timeOffset.intValue
                guard startMilliseconds >= 0 else { continue }

                let chapterName = chapter.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let baseTitle = (chapterName?.isEmpty == false) ? chapterName! : "Chapter \(chapter.chapterIndex + 1)"
                let titleName = title.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalTitle: String
                if includeTitleLabel, let titleName, !titleName.isEmpty {
                    finalTitle = "\(titleName) • \(baseTitle)"
                } else {
                    finalTitle = baseTitle
                }

                markers.append(
                    ChapterMarker(
                    id: "vlc-chapter:\(title.titleIndex):\(chapter.chapterIndex)",
                    title: finalTitle,
                    startSeconds: Double(startMilliseconds) / 1000.0
                )
                )
            }
        }

        return markers.sorted { $0.startSeconds < $1.startSeconds }
    }

    func selectAudioTrack(id: String) {
        guard let track = player.audioTracks.first(where: { mediaTrackID(for: $0, kind: .audio) == id }) else { return }
        track.isSelectedExclusively = true
    }

    func selectSubtitleTrack(id: String) {
        if id == MediaTrack.subtitleOffID {
            player.deselectAllTextTracks()
            return
        }

        guard let track = player.textTracks.first(where: { mediaTrackID(for: $0, kind: .subtitle) == id }) else { return }
        track.isSelectedExclusively = true
    }

    func selectQualityVariant(id: String) throws {
        if id == QualityVariant.auto.id {
            if let automaticQualityTrackID,
               let track = player.videoTracks.first(where: { qualityVariantID(for: $0) == automaticQualityTrackID }) {
                track.isSelectedExclusively = true
            }
            return
        }

        cacheAutomaticQualityTrackIfNeeded()
        guard let track = player.videoTracks.first(where: { qualityVariantID(for: $0) == id }) else {
            throw PlaybackRuntimeError.backendFailure("Quality variant is unavailable.")
        }
        track.isSelectedExclusively = true
    }

    func setPlaybackSpeed(_ speed: Double) {
        let clamped = max(0.5, min(speed, 2.0))
        player.rate = Float(clamped)
    }

    func setAspectRatio(_ mode: PlayerAspectRatioMode) {
        switch mode {
        case .fit, .fill, .original:
            player.videoAspectRatio = nil
        case .sixteenByNine:
            player.videoAspectRatio = "16:9"
        case .fourByThree:
            player.videoAspectRatio = "4:3"
        }
    }

    func setAudioDelay(milliseconds: Int) {
        player.currentAudioPlaybackDelay = milliseconds * 1000
    }

    func availableOutputRoutes() -> [OutputRoute] {
        outputRouteController.availableRoutes()
    }

    func selectOutputRoute(id: String) {
        outputRouteController.selectRoute(id: id)
    }

    func setVolume(_ value: Double) {
        let clamped = max(0, min(value, 1))
        player.audio?.volume = Int32((clamped * 100.0).rounded())
    }

    func setBrightness(_ value: Double) {
        guard supportsBrightnessControl else {
            _ = value
            return
        }

        let clamped = max(0, min(value, 1))
        let adjustFilter = player.adjustFilter
        adjustFilter.isEnabled = true
        adjustFilter.brightness.value = NSNumber(value: clamped * 2.0)
    }

    private func mediaDuration() -> Double? {
        let value = Double(player.media?.length.intValue ?? 0) / 1000.0
        return value > 0 ? value : nil
    }

    private func currentTime() -> Double {
        Double(player.time.intValue) / 1000.0
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                self.continuation.yield(.progress(currentTime: self.currentTime(), duration: self.mediaDuration()))
            }
        }
    }

    private func stopProgressTimer() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func mediaTrackID(for track: VLCMediaPlayer.Track, kind: MediaTrackKind) -> String {
        let prefix: String
        switch kind {
        case .audio:
            prefix = "vlc-audio"
        case .subtitle:
            prefix = "vlc-subtitle"
        }
        return "\(prefix):\(track.trackId)"
    }

    private func qualityVariantID(for track: VLCMediaPlayer.Track) -> String {
        "vlc-quality:\(track.trackId)"
    }

    private func cacheAutomaticQualityTrackIfNeeded() {
        guard automaticQualityTrackID == nil else { return }

        if let selected = player.videoTracks.first(where: \.isSelected) {
            automaticQualityTrackID = qualityVariantID(for: selected)
            return
        }

        if let first = player.videoTracks.first {
            automaticQualityTrackID = qualityVariantID(for: first)
        }
    }

    private func mediaTrackLabel(for track: VLCMediaPlayer.Track, fallbackPrefix: String) -> String {
        let preferredName = track.trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferredName.isEmpty {
            return preferredName
        }

        if let description = track.trackDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            return description
        }

        if let language = normalizedLanguageCode(track.language) {
            return "\(fallbackPrefix) (\(language.uppercased()))"
        }

        return fallbackPrefix
    }

    private func normalizedLanguageCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized.lowercased()
    }

    private var supportsBrightnessControl: Bool {
        #if os(iOS) || os(tvOS)
        true
        #else
        false
        #endif
    }

    private var supportsSystemRoutePicker: Bool {
        #if os(iOS) || os(tvOS)
        true
        #else
        false
        #endif
    }
}

@MainActor
extension VLCPlaybackBackend: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        switch newState {
        case .opening:
            continuation.yield(.buffering(true))
        case .buffering:
            continuation.yield(.buffering(true))
        case .playing:
            continuation.yield(.buffering(false))
            continuation.yield(.playing)
        case .paused:
            continuation.yield(.paused)
        case .stopped:
            if let duration = mediaDuration(), duration > 0, currentTime() >= duration - 0.5 {
                continuation.yield(.ended)
            } else {
                continuation.yield(.paused)
            }
        case .stopping:
            continuation.yield(.buffering(true))
        case .error:
            continuation.yield(.failed(PlaybackRuntimeError.backendFailure("VLC failed to play this stream.")))
        default:
            break
        }
    }
}
#else
final class VLCPlaybackBackend: NSObject, PlaybackBackend {
    let id: PlaybackBackendID = .vlc
    let player: VLCPlayerReference? = nil

    var isAvailable: Bool { false }

    func canPlay(url: URL, contentType: String, containerExtension: String?) -> Bool {
        false
    }

    func load(url: URL, autoplay: Bool) throws {
        throw PlaybackRuntimeError.noRendererAvailable
    }

    func play() {}
    func pause() {}
    func togglePlayback() {}
    func stop() {}
    func seek(to seconds: Double) {}
    func events() -> AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
#endif

@MainActor
final class AVPlaybackBackend: NSObject, PlaybackBackend {
    let id: PlaybackBackendID = .av
    let player = AVPlayer()

    var isAvailable: Bool { true }

    private let stream: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    private var timeObserver: Any?
    private var playerStateObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var failedObserver: NSObjectProtocol?
    private var endedObserver: NSObjectProtocol?
    private let outputRouteController = SystemOutputRouteController()

    private struct QualityVariantDescriptor {
        let variant: QualityVariant
        let preferredPeakBitRate: Double
        let preferredMaximumResolution: CGSize?
        let sortHeight: Double
        let sortBitRate: Double
    }

    override init() {
        var continuation: AsyncStream<PlaybackEvent>.Continuation?
        self.stream = AsyncStream<PlaybackEvent> { continuation = $0 }
        self.continuation = continuation!
        super.init()
        observePlayerState()
    }

    deinit {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
            self.failedObserver = nil
        }
        if let endedObserver {
            NotificationCenter.default.removeObserver(endedObserver)
            self.endedObserver = nil
        }

        playerStateObservation?.invalidate()
        playerStateObservation = nil

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    func canPlay(url: URL, contentType: String, containerExtension: String?) -> Bool {
        let supportedExtensions: Set<String> = [
            "m3u8", "mp4", "m4v", "mov", "mp3", "aac", "ac3", "wav"
        ]

        guard let ext = containerExtension?.lowercased(), !ext.isEmpty else {
            return false
        }
        return supportedExtensions.contains(ext)
    }

    func load(url: URL, autoplay: Bool) throws {
        cleanupItemObservers()

        let item = AVPlayerItem(url: url)
        observeItemStatus(item)
        observeItemNotifications(item)
        player.replaceCurrentItem(with: item)

        if autoplay {
            play()
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayback() {
        player.rate > 0 ? player.pause() : player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        cleanupItemObservers()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time)
    }

    func events() -> AsyncStream<PlaybackEvent> {
        stream
    }

    func capabilities() -> PlaybackCapabilities {
        let qualityDescriptors = qualityVariantDescriptors()

        return PlaybackCapabilities(
            supportsAudioTracks: mediaSelectionGroup(for: .audible) != nil,
            supportsSubtitles: mediaSelectionGroup(for: .legible) != nil,
            supportsQualitySelection: !qualityDescriptors.isEmpty,
            supportsChapterMarkers: !chapterMarkers().isEmpty,
            supportsOutputRouteSelection: supportsSystemRoutePicker,
            supportsAudioDelay: false,
            supportsBrightness: supportsBrightnessControl
        )
    }

    func audioTracks() -> [MediaTrack] {
        tracks(for: .audible, kind: .audio)
    }

    func subtitleTracks() -> [MediaTrack] {
        tracks(for: .legible, kind: .subtitle)
    }

    func qualityVariants() -> [QualityVariant] {
        let descriptors = qualityVariantDescriptors()
        guard !descriptors.isEmpty else { return [] }
        return [QualityVariant.auto] + descriptors.map(\.variant)
    }

    func chapterMarkers() -> [ChapterMarker] {
        guard let item = player.currentItem else { return [] }
        let groups = item.asset.chapterMetadataGroups(bestMatchingPreferredLanguages: preferredChapterLanguages())
        return groups.enumerated().compactMap { index, group in
            let rawStart = group.timeRange.start.seconds
            guard rawStart.isFinite else { return nil }
            let title = chapterTitle(from: group) ?? "Chapter \(index + 1)"
            let markerID = "chapter-\(index)-\(Int((rawStart * 1000).rounded()))"
            return ChapterMarker(id: markerID, title: title, startSeconds: max(0, rawStart))
        }
    }

    func availableOutputRoutes() -> [OutputRoute] {
        outputRouteController.availableRoutes()
    }

    func selectAudioTrack(id: String) {
        selectTrack(id: id, for: .audible)
    }

    func selectSubtitleTrack(id: String) {
        guard let item = player.currentItem,
              let group = mediaSelectionGroup(for: .legible)
        else { return }

        if id == MediaTrack.subtitleOffID {
            item.select(nil, in: group)
            return
        }
        selectTrack(id: id, for: .legible)
    }

    func selectQualityVariant(id: String) throws {
        guard let item = player.currentItem else {
            throw PlaybackRuntimeError.backendFailure("No active item for quality switching.")
        }

        if id == QualityVariant.auto.id {
            item.preferredPeakBitRate = 0
            item.preferredMaximumResolution = .zero
            return
        }

        guard let descriptor = qualityVariantDescriptors().first(where: { $0.variant.id == id }) else {
            throw PlaybackRuntimeError.backendFailure("Quality variant is unavailable.")
        }
        item.preferredPeakBitRate = descriptor.preferredPeakBitRate
        item.preferredMaximumResolution = descriptor.preferredMaximumResolution ?? .zero
    }

    func setPlaybackSpeed(_ speed: Double) {
        let clamped = max(0.5, min(speed, 2.0))
        if player.rate > 0 {
            player.rate = Float(clamped)
        } else {
            player.defaultRate = Float(clamped)
        }
    }

    func selectOutputRoute(id: String) {
        outputRouteController.selectRoute(id: id)
    }

    func setVolume(_ value: Double) {
        player.volume = Float(max(0, min(value, 1)))
    }

    func setBrightness(_ value: Double) {
        #if os(iOS) || os(tvOS)
        UIScreen.main.brightness = CGFloat(max(0, min(value, 1)))
        #else
        _ = value
        #endif
    }

    private func observePlayerState() {
        playerStateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch self.player.timeControlStatus {
                case .playing:
                    self.continuation.yield(.buffering(false))
                    self.continuation.yield(.playing)
                case .paused:
                    self.continuation.yield(.paused)
                case .waitingToPlayAtSpecifiedRate:
                    self.continuation.yield(.buffering(true))
                @unknown default:
                    break
                }
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let current = max(0, time.seconds)
                let duration = self.currentDuration()
                self.continuation.yield(.progress(currentTime: current, duration: duration))
            }
        }
    }

    private func observeItemStatus(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.continuation.yield(.ready(duration: self.currentDuration()))
                case .failed:
                    self.continuation.yield(.failed(item.error ?? PlaybackRuntimeError.backendFailure("AVPlayer failed to load this stream.")))
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func observeItemNotifications(_ item: AVPlayerItem) {
        let center = NotificationCenter.default
        failedObserver = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self.continuation.yield(.failed(error ?? PlaybackRuntimeError.backendFailure("AVPlayer failed during playback.")))
        }

        endedObserver = center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.continuation.yield(.ended)
        }
    }

    private func currentDuration() -> Double? {
        guard let item = player.currentItem else { return nil }
        let seconds = item.duration.seconds
        guard seconds.isFinite && seconds > 0 else { return nil }
        return seconds
    }

    private func tracks(for characteristic: AVMediaCharacteristic, kind: MediaTrackKind) -> [MediaTrack] {
        guard let group = mediaSelectionGroup(for: characteristic) else { return [] }
        return group.options.map { option in
            let languageCode = option.extendedLanguageTag ?? option.locale?.identifier
            return MediaTrack(
                id: trackID(for: option),
                kind: kind,
                languageCode: languageCode,
                label: option.displayName,
                isDefault: group.defaultOption === option,
                isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
            )
        }
    }

    private func mediaSelectionGroup(for characteristic: AVMediaCharacteristic) -> AVMediaSelectionGroup? {
        player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic)
    }

    private func selectTrack(id: String, for characteristic: AVMediaCharacteristic) {
        guard let item = player.currentItem,
              let group = mediaSelectionGroup(for: characteristic),
              let option = group.options.first(where: { trackID(for: $0) == id })
        else { return }

        item.select(option, in: group)
    }

    private func trackID(for option: AVMediaSelectionOption) -> String {
        if let language = option.extendedLanguageTag, !language.isEmpty {
            return "\(language.lowercased())::\(option.displayName.lowercased())"
        }
        if let identifier = option.locale?.identifier, !identifier.isEmpty {
            return "\(identifier.lowercased())::\(option.displayName.lowercased())"
        }
        return option.displayName.lowercased()
    }

    private func chapterTitle(from group: AVTimedMetadataGroup) -> String? {
        if let titleItem = AVMetadataItem.metadataItems(
            from: group.items,
            filteredByIdentifier: .commonIdentifierTitle
        ).first {
            return titleItem.stringValue
        }
        return group.items.first?.stringValue
    }

    private func preferredChapterLanguages() -> [String] {
        if let code = Locale.current.language.languageCode?.identifier {
            return [code]
        }
        return [Locale.current.identifier]
    }

    private var supportsBrightnessControl: Bool {
        #if os(iOS) || os(tvOS)
        true
        #else
        false
        #endif
    }

    private var supportsSystemRoutePicker: Bool {
        #if os(iOS) || os(tvOS)
        true
        #else
        false
        #endif
    }

    private func qualityVariantDescriptors() -> [QualityVariantDescriptor] {
        guard #available(macOS 12.0, iOS 15.0, tvOS 15.0, *),
              let asset = player.currentItem?.asset as? AVURLAsset
        else {
            return []
        }

        var seenIDs = Set<String>()
        let descriptors = asset.variants.compactMap { variant -> QualityVariantDescriptor? in
            let bitrateCandidates = [variant.peakBitRate, variant.averageBitRate].compactMap { $0 }.filter { $0 > 0 }
            let preferredPeakBitRate = bitrateCandidates.max() ?? 0

            let presentationSize = variant.videoAttributes?.presentationSize ?? .zero
            let hasVideoSize = presentationSize.width > 0 && presentationSize.height > 0
            let resolution = hasVideoSize
                ? "\(Int(presentationSize.width.rounded()))x\(Int(presentationSize.height.rounded()))"
                : nil
            let frameRate = variant.videoAttributes?.nominalFrameRate.flatMap { $0 > 0 ? $0 : nil }

            guard hasVideoSize || preferredPeakBitRate > 0 else { return nil }

            let identifier = qualityVariantID(
                presentationSize: presentationSize,
                bitrate: preferredPeakBitRate,
                frameRate: frameRate
            )
            guard seenIDs.insert(identifier).inserted else { return nil }

            return QualityVariantDescriptor(
                variant: QualityVariant(
                    id: identifier,
                    label: qualityVariantLabel(
                        presentationSize: presentationSize,
                        bitrate: preferredPeakBitRate
                    ),
                    bitrate: preferredPeakBitRate > 0 ? Int(preferredPeakBitRate.rounded()) : nil,
                    resolution: resolution,
                    frameRate: frameRate,
                    isAuto: false
                ),
                preferredPeakBitRate: preferredPeakBitRate,
                preferredMaximumResolution: hasVideoSize ? presentationSize : nil,
                sortHeight: hasVideoSize ? presentationSize.height : 0,
                sortBitRate: preferredPeakBitRate
            )
        }

        return descriptors.sorted {
            if $0.sortHeight == $1.sortHeight {
                return $0.sortBitRate > $1.sortBitRate
            }
            return $0.sortHeight > $1.sortHeight
        }
    }

    private func qualityVariantID(
        presentationSize: CGSize,
        bitrate: Double,
        frameRate: Double?
    ) -> String {
        let width = Int(presentationSize.width.rounded())
        let height = Int(presentationSize.height.rounded())
        let roundedBitrate = Int(bitrate.rounded())
        let roundedFrameRate = Int((frameRate ?? 0).rounded())
        return "av-quality:\(width)x\(height):\(roundedBitrate):\(roundedFrameRate)"
    }

    private func qualityVariantLabel(presentationSize: CGSize, bitrate: Double) -> String {
        let height = Int(presentationSize.height.rounded())
        if height > 0 {
            return "\(height)p"
        }

        if bitrate > 0 {
            return ByteCountFormatter.string(
                fromByteCount: Int64((bitrate / 8.0).rounded()),
                countStyle: .file
            ) + "/s"
        }

        return "Variant"
    }

    private func cleanupItemObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
            self.failedObserver = nil
        }
        if let endedObserver {
            NotificationCenter.default.removeObserver(endedObserver)
            self.endedObserver = nil
        }
    }

    private func cleanupObservers() {
        cleanupItemObservers()
        playerStateObservation?.invalidate()
        playerStateObservation = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}
