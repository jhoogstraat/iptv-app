/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays a stable player shell with interchangeable renderers.
*/

import SwiftUI
import Foundation

#if os(iOS) || os(tvOS)
import AVFoundation
import AVKit
#endif

/// A view that displays a full-window player with shared controls.
struct PlayerView: View {
    static let identifier = "PlayerView"

    @Environment(Player.self) private var player
    @Environment(Catalog.self) private var catalog
    @Environment(ProviderStore.self) private var providerStore
    @Environment(FavoritesStore.self) private var favoritesStore

    @State private var isShowingControls = true
    @State private var scrubTime: Double?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var favoriteStateTask: Task<Void, Never>?
    @State private var isFavorite = false

    #if os(iOS)
    @State private var mobileSheet: MobileSheet?
    @State private var iOSScrubSession: IOSScrubSession?
    #endif

    #if os(tvOS)
    @State private var tvPanel: TVPanel?
    @FocusState private var focusedControl: TVControlFocus?
    #endif

    private var sliderValue: Binding<Double> {
        Binding(
            get: { scrubTime ?? player.currentTime },
            set: { scrubTime = $0 }
        )
    }

    private var sliderRange: ClosedRange<Double> {
        let upper = max(player.duration ?? player.currentTime, 1)
        return 0...upper
    }

    private var outputRouteSelectionBinding: Binding<String> {
        Binding(
            get: { player.selectedOutputRouteID ?? player.outputRoutes.first?.id ?? "" },
            set: { newID in
                guard !newID.isEmpty else { return }
                player.selectOutputRoute(id: newID)
            }
        )
    }

    private var currentVideoInfo: VideoInfo? {
        guard let currentItem = player.currentItem, currentItem.xtreamContentType == .vod else { return nil }
        return catalog.vodInfo[currentItem]
    }

    private var currentSeriesInfo: XtreamSeries? {
        guard let currentItem = player.currentItem, currentItem.xtreamContentType == .series else { return nil }
        return catalog.cachedSeriesInfo(for: currentItem)
    }

    private var eyebrowText: String? {
        if let genre = currentVideoInfo?.genre.nonEmptyTrimmed {
            return genre
        }

        if let genre = currentSeriesInfo?.info.genre.nonEmptyTrimmed {
            return genre
        }

        let categoryNames = player.currentItem?.categories
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? []

        return categoryNames.first
    }

    private var synopsisText: String? {
        if let plot = currentVideoInfo?.plot.nonEmptyTrimmed {
            return plot
        }

        if let plot = currentSeriesInfo?.info.plot.nonEmptyTrimmed {
            return plot
        }

        return nil
    }

    private var primaryDisplayQuality: QualityVariant? {
        if let selected = player.qualityVariants.first(where: { $0.id == player.selectedQualityVariantID && !$0.isAuto }) {
            return selected
        }

        return player.qualityVariants.first(where: { !$0.isAuto })
    }

    private var streamBadges: [OverlayBadge] {
        var badges: [OverlayBadge] = []

        if let backend = player.activeBackendID?.rawValue.uppercased() {
            badges.append(OverlayBadge(label: backend))
        }

        if let resolution = primaryDisplayQuality?.resolution?.nonEmptyTrimmed ?? currentVideoInfo?.videoResolution.nonEmptyTrimmed {
            badges.append(OverlayBadge(label: resolution))
        }

        let frameRate = primaryDisplayQuality?.frameRate ?? currentVideoInfo?.videoFrameRate
        if let frameRate, frameRate > 0 {
            badges.append(OverlayBadge(label: "\(frameRate.formatted(.number.precision(.fractionLength(0)))) FPS"))
        }

        if let audio = preferredAudioBadgeText?.nonEmptyTrimmed {
            badges.append(OverlayBadge(label: audio))
        }

        return badges
    }

    private var preferredAudioBadgeText: String? {
        if let description = currentVideoInfo?.audioDescription.nonEmptyTrimmed {
            return description
        }

        if let selectedTrack = player.audioTracks.first(where: { $0.id == player.selectedAudioTrackID }) {
            return selectedTrack.label
        }

        if player.audioTracks.count > 1 {
            return "Multi Audio"
        }

        return nil
    }

    private var displayTitle: String {
        guard let rawTitle = player.currentItem?.name else { return "No item loaded" }
        return LanguageTaggedText(rawTitle).displayName
    }

    private var controlsFadeAnimation: Animation {
        .easeInOut(duration: 0.28)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            PlayerRendererContainer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControlsVisibility()
                }

            if isShowingControls {
                overlayBackground
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .transition(.opacity)

                controlsOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            scheduleAutoHideIfNeeded()
            player.refreshOutputRoutes()
        }
        .onChange(of: player.isPlaying) { _, _ in
            scheduleAutoHideIfNeeded()
        }
        .onChange(of: player.activeBackendID) { _, _ in
            player.refreshOutputRoutes()
        }
        .onChange(of: player.currentItem?.id) { _, _ in
            scheduleFavoriteStateRefresh()
            player.refreshOutputRoutes()
        }
        #if os(iOS) || os(tvOS)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            player.refreshOutputRoutes()
        }
        #endif
        .onDisappear {
            hideControlsTask?.cancel()
            favoriteStateTask?.cancel()
        }
        .task {
            scheduleFavoriteStateRefresh()
        }
        #if os(tvOS)
        .onPlayPauseCommand {
            if isShowingControls {
                player.togglePlayback()
            } else {
                revealControls()
            }
        }
        .onExitCommand {
            revealControls()
        }
        #endif
        #if os(iOS)
        .sheet(item: $mobileSheet) { sheet in
            mobileSheetView(sheet)
        }
        #endif
    }

    @ViewBuilder
    private var controlsOverlay: some View {
        ZStack {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    hideControls()
                }

            #if os(tvOS)
            tvControlsOverlay
            #elseif os(macOS)
            macControlsOverlay
            #else
            mobileControlsOverlay
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                player.close()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.headline.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif
            .accessibilityIdentifier("player.close")

            Spacer()
        }
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let eyebrowText {
                Text(eyebrowText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }

            Text(displayTitle)
                .font(titleFont)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(2)

            if let synopsisText {
                Text(synopsisText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var streamBadgeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(streamBadges) { badge in
                    Text(badge.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .scrollDisabled(true)
    }

    private var titleFont: Font {
        #if os(tvOS)
        .largeTitle
        #elseif os(macOS)
        .title
        #else
        .title2
        #endif
    }

    private var transportControls: some View {
        HStack(spacing: 24) {
            Button {
                let newTime = max((scrubTime ?? player.currentTime) - 10, 0)
                scrubTime = newTime
                player.seek(to: newTime)
            } label: {
                Image(systemName: "10.arrow.trianglehead.counterclockwise")
            }
            .accessibilityIdentifier("player.seekBack")
            #if os(macOS)
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            #endif

            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .accessibilityIdentifier("player.playPause")
            #if os(macOS)
            .keyboardShortcut(.space, modifiers: [])
            #endif

            Button {
                let current = scrubTime ?? player.currentTime
                let fallbackUpper = current + 10
                let limit = player.duration ?? fallbackUpper
                let newTime = min(current + 10, limit)
                scrubTime = newTime
                player.seek(to: newTime)
            } label: {
                Image(systemName: "10.arrow.trianglehead.clockwise")
            }
            .accessibilityIdentifier("player.seekForward")
            #if os(macOS)
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            #endif
        }
        .font(.title2)
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    private var timelineControls: some View {
        VStack(spacing: 8) {
            #if os(iOS)
            iOSTimelineScrubber
            #else
            Slider(
                value: sliderValue,
                in: sliderRange,
                onEditingChanged: { editing in
                    if editing {
                        hideControlsTask?.cancel()
                    } else {
                        let value = scrubTime ?? player.currentTime
                        player.seek(to: value)
                        scrubTime = nil
                        scheduleAutoHideIfNeeded()
                    }
                }
            )
            .accessibilityIdentifier("player.timeline")
            #endif

            HStack {
                Text(player.formattedCurrentTime)
                Spacer()
                Text(player.formattedDuration)
                Spacer()
                Text(player.formattedRemainingTime)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    #if os(iOS)
    private var iOSTimelineScrubber: some View {
        GeometryReader { proxy in
            let currentValue = scrubTime ?? player.currentTime
            let fraction = timelineFraction(for: currentValue)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: 6)

                Capsule()
                    .fill(.white)
                    .frame(width: max(proxy.size.width * fraction, 12), height: 6)

                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .offset(x: thumbOffset(in: proxy.size.width, fraction: fraction))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        updateIOSScrub(at: value.location, size: proxy.size)
                    }
                    .onEnded { _ in
                        commitIOSScrub()
                    }
            )
            .accessibilityIdentifier("player.timeline")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(player.formattedCurrentTime) of \(player.formattedDuration)")
            .accessibilityAdjustableAction { direction in
                let delta = 10.0
                switch direction {
                case .increment:
                    player.seek(to: min(player.currentTime + delta, sliderRange.upperBound))
                case .decrement:
                    player.seek(to: max(player.currentTime - delta, 0))
                @unknown default:
                    break
                }
            }
        }
        .frame(height: 28)
    }
    #endif

    private var statusMessages: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let errorMessage = player.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            if let controlMessage = player.controlMessage {
                Text(controlMessage)
                    .font(.subheadline)
                    .foregroundStyle(.yellow)

                if player.canRetryEpisodeSwitch {
                    Button("Retry") {
                        player.retryEpisodeSwitch()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("player.retryEpisodeSwitch")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if os(iOS)
    private var mobileControlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                infoPanel

                timelineControls

                transportStrip

                HStack(spacing: 10) {
                    favoriteControlButton
                    audioControlChip
                    subtitleControlChip
                    moreControlChip
                    if player.episodeOptions.count > 1 {
                        controlChip("Episodes", icon: "list.number") {
                            mobileSheet = .episodes
                        }
                        .accessibilityIdentifier("player.chip.episodes")
                    }
                }

                if player.outputRoutes.count > 1 {
                    outputRouteSummary
                }

                statusMessages
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }
    #endif

    #if os(macOS)
    private var macControlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 24)
                .padding(.top, 20)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                infoPanel

                HStack(alignment: .center, spacing: 20) {
                    if !streamBadges.isEmpty {
                        streamBadgeRow
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .center, spacing: 16) {
                        transportStrip
                        menuStrip
                    }
                    .padding(.trailing, -24)
                }

                timelineControls

                if player.outputRoutes.count > 1 {
                    outputRouteSummary
                }

                statusMessages
            }
            .padding(.top, 24)
            .padding(.leading, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }
    #endif

    #if os(tvOS)
    private var tvControlsOverlay: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                topBar

                infoPanel

                timelineControls

                transportStrip
                    .focused($focusedControl, equals: .transport)

                HStack(spacing: 12) {
                    favoriteControlButton
                        .focused($focusedControl, equals: .favorite)

                    Button("Audio") {
                        tvPanel = .audio
                    }
                    .focused($focusedControl, equals: .audio)

                    Button("Subtitles") {
                        tvPanel = .subtitles
                    }
                    .focused($focusedControl, equals: .subtitles)

                    Button("More") {
                        tvPanel = .more
                    }
                    .focused($focusedControl, equals: .more)

                    if player.episodeOptions.count > 1 {
                        Button("Episodes") {
                            tvPanel = .episodes
                        }
                        .focused($focusedControl, equals: .episodes)
                    }
                }

                if player.outputRoutes.count > 1 {
                    outputRouteSummary
                }

                statusMessages
            }

            if let panel = tvPanel {
                tvPanelView(panel)
                    .frame(width: 360)
                    .padding(18)
                    .background(.black.opacity(0.55))
                    .clipShape(.rect(cornerRadius: 16))
            }
        }
        .padding(28)
        .foregroundStyle(.white)
        .onAppear {
            focusedControl = .transport
        }
    }
    #endif

    private var transportStrip: some View {
        transportControls
            .font(.title2)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.white.opacity(0.12))
            .clipShape(Capsule())
    }

    private var favoriteControlButton: some View {
        Button {
            Task { await toggleFavorite() }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.headline.weight(.semibold))
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.12))
                .clipShape(Circle())
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .disabled(player.currentItem == nil)
        .accessibilityIdentifier("player.favorite")
    }

    #if os(iOS)
    private var audioControlChip: some View {
        controlChip("Audio", icon: "speaker.wave.2") {
            mobileSheet = .audio
        }
        .accessibilityIdentifier("player.chip.audio")
    }

    private var subtitleControlChip: some View {
        controlChip("Subtitles", icon: "captions.bubble") {
            mobileSheet = .subtitles
        }
        .accessibilityIdentifier("player.chip.subtitles")
    }

    private var moreControlChip: some View {
        controlChip("More", icon: "ellipsis") {
            mobileSheet = .more
        }
        .accessibilityIdentifier("player.chip.more")
    }
    #endif

    #if os(macOS)
    private var menuStrip: some View {
        HStack(spacing: 10) {
            favoriteControlButton

            Menu("Audio") {
                audioTrackMenuContent
            }
            .disabled(player.currentItem == nil)

            Menu("Subtitles") {
                subtitleMenuContent
            }
            .disabled(player.currentItem == nil)

            Menu("More") {
                moreMenuContent
            }
            .disabled(player.currentItem == nil)

            if player.episodeOptions.count > 1 {
                Menu("Episodes") {
                    episodeMenuContent
                }
            }
        }
        .menuStyle(.borderlessButton)
    }
    #endif

    private var outputRouteSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "airplayaudio")
                .font(.caption.weight(.semibold))
            Text(activeOutputRouteName)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var activeOutputRouteName: String {
        player.outputRoutes.first(where: { $0.id == player.selectedOutputRouteID || $0.isActive })?.name
            ?? "System Output"
    }

    private var overlayBackground: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.44))

            LinearGradient(
                colors: [
                    .black.opacity(0.18),
                    .black.opacity(0.42),
                    .black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    #if os(iOS)
    private func controlChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.14))
                .clipShape(Capsule())
        }
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private func mobileSheetView(_ sheet: MobileSheet) -> some View {
        switch sheet {
        case .audio:
            NavigationStack {
                List {
                    audioTrackListRows
                }
                .navigationTitle("Audio")
            }
            .presentationDetents([.medium, .large])

        case .subtitles:
            NavigationStack {
                List {
                    subtitleTrackListRows
                }
                .navigationTitle("Subtitles")
            }
            .presentationDetents([.medium, .large])

        case .more:
            NavigationStack {
                List {
                    Section("Playback") {
                        speedPicker
                        aspectRatioPicker
                        audioDelayStepper
                    }

                    Section("Output") {
                        outputRouteRow
                    }

                    Section("Display") {
                        volumeSlider
                        brightnessSlider
                    }

                    Section("Sleep Timer") {
                        sleepTimerRows
                    }
                }
                .navigationTitle("More")
            }
            .presentationDetents([.medium, .large])

        case .episodes:
            NavigationStack {
                List {
                    episodeListRows
                }
                .navigationTitle("Episodes")
            }
            .presentationDetents([.medium, .large])
        }
    }
    #endif

    #if os(tvOS)
    @ViewBuilder
    private func tvPanelView(_ panel: TVPanel) -> some View {
        switch panel {
        case .audio:
            List {
                audioTrackListRows
            }
        case .subtitles:
            List {
                subtitleTrackListRows
            }
        case .more:
            List {
                speedPicker
                aspectRatioPicker
                audioDelayStepper
                volumeSlider
                brightnessSlider
                outputRouteRow
                sleepTimerRows
            }
        case .episodes:
            List {
                episodeListRows
            }
        }
    }
    #endif

    @ViewBuilder
    private var audioTrackListRows: some View {
        if player.capabilities.supportsAudioTracks {
            ForEach(player.audioTracks) { track in
                Button {
                    player.selectAudioTrack(id: track.id)
                } label: {
                    HStack {
                        Text(trackLabel(track))
                        Spacer()
                        if track.id == player.selectedAudioTrackID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if player.audioTracks.isEmpty {
                Text("No audio tracks available")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(player.unavailableFeatureMessages.first(where: { $0.hasPrefix("Audio:") }) ?? "Unsupported by current backend")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var subtitleTrackListRows: some View {
        if player.capabilities.supportsSubtitles {
            Button {
                player.selectSubtitleTrack(id: MediaTrack.subtitleOffID)
            } label: {
                HStack {
                    Text("Off")
                    Spacer()
                    if player.selectedSubtitleTrackID == MediaTrack.subtitleOffID {
                        Image(systemName: "checkmark")
                    }
                }
            }

            ForEach(player.subtitleTracks) { track in
                Button {
                    player.selectSubtitleTrack(id: track.id)
                } label: {
                    HStack {
                        Text(trackLabel(track))
                        Spacer()
                        if track.id == player.selectedSubtitleTrackID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if player.subtitleTracks.isEmpty {
                Text("No subtitle tracks available")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(player.unavailableFeatureMessages.first(where: { $0.hasPrefix("Subtitles:") }) ?? "Unsupported by current backend")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var qualityListRows: some View {
        if player.capabilities.supportsQualitySelection {
            ForEach(player.qualityVariants) { variant in
                Button {
                    player.selectQualityVariant(id: variant.id)
                } label: {
                    HStack {
                        Text(qualityLabel(variant))
                        Spacer()
                        if variant.id == player.selectedQualityVariantID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } else {
            Text(player.unavailableFeatureMessages.first(where: { $0.hasPrefix("Quality:") }) ?? "Quality switching unavailable for this stream")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chapterListRows: some View {
        if player.capabilities.supportsChapterMarkers {
            ForEach(player.chapterMarkers) { chapter in
                Button {
                    player.jumpToChapter(id: chapter.id)
                } label: {
                    HStack {
                        Text(chapter.title)
                        Spacer()
                        Text(formatTime(chapter.startSeconds))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if player.chapterMarkers.isEmpty {
                Text("No chapter metadata available")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(player.unavailableFeatureMessages.first(where: { $0.hasPrefix("Chapters:") }) ?? "Chapter navigation unavailable")
                .foregroundStyle(.secondary)
        }
    }

    private var speedPicker: some View {
        Picker("Speed", selection: Binding(
            get: { player.playbackSpeed },
            set: { player.setPlaybackSpeed($0) }
        )) {
            Text("0.5x").tag(0.5)
            Text("0.75x").tag(0.75)
            Text("1.0x").tag(1.0)
            Text("1.25x").tag(1.25)
            Text("1.5x").tag(1.5)
            Text("2.0x").tag(2.0)
        }
    }

    private var aspectRatioPicker: some View {
        Picker("Aspect Ratio", selection: Binding(
            get: { player.aspectRatioMode },
            set: { player.setAspectRatio($0) }
        )) {
            ForEach(player.supportedAspectRatioModes) { mode in
                Text(mode.label).tag(mode)
            }
        }
    }

    private var audioDelayStepper: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Audio Delay")
                Spacer()
                Stepper(
                    "\(player.audioDelayMilliseconds) ms",
                    value: Binding(
                        get: { player.audioDelayMilliseconds },
                        set: { player.setAudioDelay(milliseconds: $0) }
                    ),
                    in: -5000...5000,
                    step: 50
                )
                #if !os(macOS)
                .labelsHidden()
                #endif
                .disabled(!player.capabilities.supportsAudioDelay)
            }

            HStack {
                Button("Reset to 0") {
                    player.resetAudioDelay()
                }
                .disabled(!player.capabilities.supportsAudioDelay || player.audioDelayMilliseconds == 0)

                if !player.capabilities.supportsAudioDelay {
                    Text("Unsupported by current backend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var volumeSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volume")
            Slider(
                value: Binding(
                    get: { player.volume },
                    set: { player.setVolume($0) }
                ),
                in: 0...1
            )
            .accessibilityIdentifier("player.volume")
        }
    }

    @ViewBuilder
    private var brightnessSlider: some View {
        if player.capabilities.supportsBrightness {
            VStack(alignment: .leading, spacing: 8) {
                Text("Brightness")
                Slider(
                    value: Binding(
                        get: { player.brightness },
                        set: { player.setBrightness($0) }
                    ),
                    in: 0...1
                )
                .accessibilityIdentifier("player.brightness")
            }
        } else {
            Text("Brightness unavailable")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var outputRouteRow: some View {
        #if os(iOS) || os(tvOS)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output Device")
                Spacer()
                if player.capabilities.supportsOutputRouteSelection, !player.outputRoutes.isEmpty {
                    Picker("Route", selection: outputRouteSelectionBinding) {
                        ForEach(player.outputRoutes) { route in
                            Text(menuLabel(route.name, selected: route.id == player.selectedOutputRouteID || route.isActive))
                                .tag(route.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityIdentifier("player.outputRouteSelection")
                }

                OutputRoutePickerButton()
                    .frame(width: 38, height: 30)
                    .disabled(!player.capabilities.supportsOutputRouteSelection)
            }

            if !player.capabilities.supportsOutputRouteSelection {
                Text("Output route switching is unavailable for this stream/backend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if player.outputRoutes.isEmpty {
                Text("No output routes discovered yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        #else
        Text("Output route picker unavailable on this platform")
            .foregroundStyle(.secondary)
        #endif
    }

    @ViewBuilder
    private var sleepTimerRows: some View {
        ForEach(SleepTimerOption.allCases) { option in
            Button {
                player.setSleepTimer(option)
            } label: {
                HStack {
                    Text(option.label)
                    Spacer()
                    if player.sleepTimerOption == option {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }

        if let fireDate = player.sleepTimerEndsAt {
            HStack {
                Text("Ends")
                Spacer()
                Text(fireDate, style: .time)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var episodeListRows: some View {
        if player.episodeOptions.count > 1 {
            ForEach(player.episodeOptions, id: \.id) { episode in
                Button {
                    player.quickSwitchEpisode(id: episode.id)
                } label: {
                    HStack {
                        Text(episode.name)
                            .lineLimit(1)
                        Spacer()
                        if episode.id == player.currentItem?.id {
                            Image(systemName: "play.fill")
                        }
                    }
                }
            }
        } else {
            Text("No alternate episodes available")
                .foregroundStyle(.secondary)
        }
    }

    #if os(macOS)
    @ViewBuilder
    private var audioTrackMenuContent: some View {
        if player.capabilities.supportsAudioTracks {
            if player.audioTracks.isEmpty {
                Text("No tracks")
            } else {
                ForEach(player.audioTracks) { track in
                    Button(menuLabel(trackLabel(track), selected: track.id == player.selectedAudioTrackID)) {
                        player.selectAudioTrack(id: track.id)
                    }
                }
            }
        } else {
            Text(player.unavailableFeatureMessages.first(where: { $0.hasPrefix("Audio:") }) ?? "Unsupported")
        }
    }

    @ViewBuilder
    private var subtitleMenuContent: some View {
        if player.capabilities.supportsSubtitles {
            Button(menuLabel("Off", selected: player.selectedSubtitleTrackID == MediaTrack.subtitleOffID)) {
                player.selectSubtitleTrack(id: MediaTrack.subtitleOffID)
            }

            ForEach(player.subtitleTracks) { track in
                Button(menuLabel(trackLabel(track), selected: track.id == player.selectedSubtitleTrackID)) {
                    player.selectSubtitleTrack(id: track.id)
                }
            }
        } else {
            Text(player.unavailableFeatureMessages.first(where: { $0.hasPrefix("Subtitles:") }) ?? "Unsupported")
        }
    }

    @ViewBuilder
    private var qualityMenuContent: some View {
        if player.capabilities.supportsQualitySelection {
            ForEach(player.qualityVariants) { variant in
                Button(menuLabel(qualityLabel(variant), selected: variant.id == player.selectedQualityVariantID)) {
                    player.selectQualityVariant(id: variant.id)
                }
            }
        } else {
            Text(player.unavailableFeatureMessages.first(where: { $0.hasPrefix("Quality:") }) ?? "Unsupported")
        }
    }

    @ViewBuilder
    private var chapterMenuContent: some View {
        if player.capabilities.supportsChapterMarkers {
            ForEach(player.chapterMarkers) { chapter in
                Button(menuLabel(chapter.title, selected: false)) {
                    player.jumpToChapter(id: chapter.id)
                }
            }
        } else {
            Text(player.unavailableFeatureMessages.first(where: { $0.hasPrefix("Chapters:") }) ?? "Unsupported")
        }
    }

    @ViewBuilder
    private var outputRouteMenuContent: some View {
        if player.capabilities.supportsOutputRouteSelection {
            if player.outputRoutes.isEmpty {
                Text("No routes available")
            } else {
                ForEach(player.outputRoutes) { route in
                    Button(menuLabel(route.name, selected: route.id == player.selectedOutputRouteID)) {
                        player.selectOutputRoute(id: route.id)
                    }
                }
            }
        } else {
            Text(player.unavailableFeatureMessages.first(where: { $0.hasPrefix("Output device:") }) ?? "Unsupported")
        }
    }

    private var moreMenuContent: some View {
        Group {
            if player.capabilities.supportsOutputRouteSelection, !player.outputRoutes.isEmpty {
                Menu("Output") {
                    outputRouteMenuContent
                }
            }

            Menu("Speed") {
                speedMenuContent
            }

            Menu("Aspect") {
                aspectRatioMenuContent
            }

            Menu("Sleep") {
                sleepTimerMenuContent
            }

            if player.capabilities.supportsAudioDelay {
                Button("Reset Audio Delay") {
                    player.resetAudioDelay()
                }
            }
        }
    }

    private var aspectRatioMenuContent: some View {
        Group {
            ForEach(player.supportedAspectRatioModes) { mode in
                Button(mode.label) {
                    player.setAspectRatio(mode)
                }
            }
        }
    }

    private var speedMenuContent: some View {
        Group {
            Button("0.5x") { player.setPlaybackSpeed(0.5) }
            Button("0.75x") { player.setPlaybackSpeed(0.75) }
            Button("1.0x") { player.setPlaybackSpeed(1.0) }
            Button("1.25x") { player.setPlaybackSpeed(1.25) }
            Button("1.5x") { player.setPlaybackSpeed(1.5) }
            Button("2.0x") { player.setPlaybackSpeed(2.0) }
        }
    }

    private var sleepTimerMenuContent: some View {
        Group {
            ForEach(SleepTimerOption.allCases) { option in
                Button(option.label) {
                    player.setSleepTimer(option)
                }
            }
        }
    }

    @ViewBuilder
    private var episodeMenuContent: some View {
        if player.episodeOptions.count > 1 {
            ForEach(player.episodeOptions, id: \.id) { episode in
                Button(episode.name) {
                    player.quickSwitchEpisode(id: episode.id)
                }
            }
        } else {
            Text("None")
        }
    }
    #endif

    private func menuLabel(_ title: String, selected: Bool) -> String {
        selected ? "✓ \(title)" : title
    }

    private func trackLabel(_ track: MediaTrack) -> String {
        var parts = [track.label]
        if let languageCode = track.languageCode, !languageCode.isEmpty {
            parts.append(languageCode)
        }
        if track.isDefault {
            parts.append("Default")
        }
        if track.isForced {
            parts.append("Forced")
        }
        return parts.joined(separator: " • ")
    }

    private func qualityLabel(_ variant: QualityVariant) -> String {
        var parts = [variant.label]
        if let resolution = variant.resolution {
            parts.append(resolution)
        }
        if let bitrate = variant.bitrate {
            parts.append("\(bitrate / 1000) kbps")
        }
        if let frameRate = variant.frameRate {
            parts.append("\(frameRate.formatted(.number.precision(.fractionLength(0)))) fps")
        }
        return parts.joined(separator: " • ")
    }

    private func timelineFraction(for value: Double) -> CGFloat {
        let upperBound = sliderRange.upperBound
        guard upperBound > 0 else { return 0 }
        let clamped = min(max(value, sliderRange.lowerBound), upperBound)
        return CGFloat(clamped / upperBound)
    }

    private func thumbOffset(in width: CGFloat, fraction: CGFloat) -> CGFloat {
        let thumbSize: CGFloat = 18
        let availableWidth = max(width - thumbSize, 0)
        return min(max(availableWidth * fraction, 0), availableWidth)
    }

    private func scheduleAutoHideIfNeeded() {
        hideControlsTask?.cancel()
        guard player.isPlaying else { return }

        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(controlsFadeAnimation) {
                isShowingControls = false
            }
        }
    }

    private func toggleControlsVisibility() {
        if isShowingControls {
            hideControls()
        } else {
            revealControls()
        }
    }

    private func hideControls() {
        hideControlsTask?.cancel()
        withAnimation(controlsFadeAnimation) {
            isShowingControls = false
        }
    }

    private func revealControls() {
        withAnimation(controlsFadeAnimation) {
            isShowingControls = true
        }
        scheduleAutoHideIfNeeded()
        #if os(tvOS)
        focusedControl = .transport
        #endif
    }

    private func scheduleFavoriteStateRefresh() {
        favoriteStateTask?.cancel()
        favoriteStateTask = Task {
            guard let video = player.currentItem,
                  let config = try? providerStore.requiredConfiguration()
            else {
                guard !Task.isCancelled else { return }
                isFavorite = false
                return
            }

            let expectedVideoID = video.id
            let fingerprint = ProviderCacheFingerprint.make(from: config)
            let contains = await favoritesStore.contains(video: video, providerFingerprint: fingerprint)

            guard !Task.isCancelled else { return }
            guard player.currentItem?.id == expectedVideoID else { return }
            isFavorite = contains
        }
    }

    private func toggleFavorite() async {
        guard let video = player.currentItem,
              let config = try? providerStore.requiredConfiguration()
        else { return }

        let fingerprint = ProviderCacheFingerprint.make(from: config)
        let targetState = !isFavorite
        await favoritesStore.setFavorite(video: video, providerFingerprint: fingerprint, isFavorite: targetState)
        guard player.currentItem?.id == video.id else { return }
        isFavorite = targetState
    }

    #if os(iOS)
    private func updateIOSScrub(at location: CGPoint, size: CGSize) {
        guard sliderRange.upperBound > 0 else { return }

        hideControlsTask?.cancel()

        let clampedX = min(max(location.x, 0), size.width)
        let trackFraction = size.width > 0 ? clampedX / size.width : 0
        let anchorTime = sliderRange.upperBound * Double(trackFraction)

        if iOSScrubSession == nil {
            iOSScrubSession = IOSScrubSession(
                anchorTime: anchorTime,
                anchorLocation: CGPoint(x: clampedX, y: location.y),
                trackWidth: max(size.width, 1),
                trackCenterY: size.height / 2
            )
            scrubTime = anchorTime
            return
        }

        guard let session = iOSScrubSession else { return }
        let verticalDistance = abs(location.y - session.trackCenterY)
        let speedMultiplier = scrubVelocityMultiplier(for: verticalDistance)
        let horizontalDelta = Double(clampedX - session.anchorLocation.x)
        let secondsPerPoint = sliderRange.upperBound / Double(session.trackWidth)
        let nextValue = session.anchorTime + (horizontalDelta * secondsPerPoint * speedMultiplier)
        scrubTime = min(max(nextValue, sliderRange.lowerBound), sliderRange.upperBound)
    }

    private func commitIOSScrub() {
        let target = min(max(scrubTime ?? player.currentTime, sliderRange.lowerBound), sliderRange.upperBound)
        player.seek(to: target)
        scrubTime = nil
        iOSScrubSession = nil
        scheduleAutoHideIfNeeded()
    }

    private func scrubVelocityMultiplier(for verticalDistance: CGFloat) -> Double {
        let normalized = min(max(verticalDistance / 36, 0), 5)
        return 1 + Double(normalized * 1.4)
    }
    #endif

    private func formatTime(_ rawSeconds: Double) -> String {
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

#if os(iOS)
private enum MobileSheet: String, Identifiable {
    case audio
    case subtitles
    case more
    case episodes

    var id: String { rawValue }
}

private struct IOSScrubSession {
    let anchorTime: Double
    let anchorLocation: CGPoint
    let trackWidth: CGFloat
    let trackCenterY: CGFloat
}
#endif

#if os(tvOS)
private enum TVPanel {
    case audio
    case subtitles
    case more
    case episodes
}

private enum TVControlFocus: Hashable {
    case favorite
    case transport
    case audio
    case subtitles
    case more
    case episodes
}
#endif

private struct OverlayBadge: Identifiable {
    let id = UUID()
    let label: String
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if os(iOS) || os(tvOS)
private struct OutputRoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        view.accessibilityIdentifier = "player.outputRoutePicker"
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

#Preview(traits: .previewData) {
    PlayerView()
}
