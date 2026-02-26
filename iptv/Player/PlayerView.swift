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
    @Environment(ProviderStore.self) private var providerStore
    @Environment(FavoritesStore.self) private var favoritesStore

    @State private var isShowingControls = true
    @State private var scrubTime: Double?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var favoriteStateTask: Task<Void, Never>?
    @State private var isFavorite = false

    #if os(iOS)
    @State private var mobileSheet: MobileSheet?
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

    private var mediaControlsSupported: Bool {
        player.capabilities.supportsAudioTracks || player.capabilities.supportsSubtitles
    }

    private var qualityControlsSupported: Bool {
        player.capabilities.supportsQualitySelection
    }

    private var chapterControlsSupported: Bool {
        player.capabilities.supportsChapterMarkers
    }

    var body: some View {
        ZStack {
            PlayerRendererContainer()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingControls.toggle()
                    }
                    scheduleAutoHideIfNeeded()
                }

            if isShowingControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
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
        #if os(tvOS)
        tvControlsOverlay
        #elseif os(macOS)
        macControlsOverlay
        #else
        mobileControlsOverlay
        #endif
    }

    #if !os(tvOS)
    private var topHeader: some View {
        HStack(spacing: 12) {
            Button {
                player.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("player.close")

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentItem?.name ?? "No item loaded")
                    .font(.headline)
                    .lineLimit(1)
                Text("Backend: \(player.activeBackendID?.rawValue.uppercased() ?? "N/A")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await toggleFavorite() }
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
            }
            .buttonStyle(.bordered)
            .disabled(player.currentItem == nil)
            .accessibilityIdentifier("player.favorite")

            if player.isBuffering {
                Label("Buffering", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
            }
        }
    }
    #endif

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
        .font(.largeTitle)
    }

    private var timelineControls: some View {
        VStack(spacing: 8) {
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

            if let unsupported = player.unsupportedFeaturesSummary {
                Text(unsupported)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if os(iOS)
    private var mobileControlsOverlay: some View {
        VStack(spacing: 16) {
            topHeader

            Spacer()

            transportControls

            timelineControls

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    controlChip("Media", icon: "music.note.list") {
                        mobileSheet = .media
                    }
                    .disabled(!mediaControlsSupported)
                    .accessibilityIdentifier("player.chip.media")
                    controlChip("Quality", icon: "dial.medium") {
                        mobileSheet = .quality
                    }
                    .disabled(!qualityControlsSupported)
                    .accessibilityIdentifier("player.chip.quality")
                    controlChip("Chapters", icon: "list.bullet.rectangle") {
                        mobileSheet = .chapters
                    }
                    .disabled(!chapterControlsSupported)
                    .accessibilityIdentifier("player.chip.chapters")
                    controlChip("Settings", icon: "slider.horizontal.3") {
                        mobileSheet = .settings
                    }
                    .accessibilityIdentifier("player.chip.settings")
                    controlChip("Sleep", icon: "moon") {
                        mobileSheet = .sleep
                    }
                    .accessibilityIdentifier("player.chip.sleep")
                    controlChip("Episodes", icon: "list.number") {
                        mobileSheet = .episodes
                    }
                    .disabled(player.episodeOptions.count <= 1)
                    .accessibilityIdentifier("player.chip.episodes")
                }
                .padding(.horizontal, 1)
            }

            statusMessages
        }
        .padding()
        .foregroundStyle(.white)
        .background(.black.opacity(0.45))
        .contentShape(Rectangle())
        .onTapGesture {
            scheduleAutoHideIfNeeded()
        }
    }
    #endif

    #if os(macOS)
    private var macControlsOverlay: some View {
        VStack(spacing: 14) {
            topHeader

            Spacer()

            transportControls

            timelineControls

            HStack(spacing: 10) {
                Menu("Audio") {
                    audioTrackMenuContent
                }
                .disabled(!player.capabilities.supportsAudioTracks)

                Menu("Subtitles") {
                    subtitleMenuContent
                }
                .disabled(!player.capabilities.supportsSubtitles)

                Menu("Quality") {
                    qualityMenuContent
                }
                .disabled(!player.capabilities.supportsQualitySelection)

                Menu("Chapters") {
                    chapterMenuContent
                }
                .disabled(!player.capabilities.supportsChapterMarkers)

                Menu("Output") {
                    outputRouteMenuContent
                }
                .disabled(!player.capabilities.supportsOutputRouteSelection || player.outputRoutes.isEmpty)

                Menu("Aspect") {
                    aspectRatioMenuContent
                }

                Menu("Speed") {
                    speedMenuContent
                }

                Menu("Sleep") {
                    sleepTimerMenuContent
                }

                Menu("Episodes") {
                    episodeMenuContent
                }
                .disabled(player.episodeOptions.count <= 1)
            }

            HStack(spacing: 12) {
                Text("Volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { player.volume },
                        set: { player.setVolume($0) }
                    ),
                    in: 0...1
                )

                Text("Audio Delay")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("\(player.audioDelayMilliseconds) ms", value: Binding(
                    get: { player.audioDelayMilliseconds },
                    set: { player.setAudioDelay(milliseconds: $0) }
                ), in: -5000...5000, step: 50)
                .labelsHidden()
                .disabled(!player.capabilities.supportsAudioDelay)

                Button("Reset") {
                    player.resetAudioDelay()
                }
                .buttonStyle(.bordered)
                .disabled(!player.capabilities.supportsAudioDelay || player.audioDelayMilliseconds == 0)
            }

            statusMessages
        }
        .padding()
        .foregroundStyle(.white)
        .background(.black.opacity(0.45))
        .contentShape(Rectangle())
        .onTapGesture {
            scheduleAutoHideIfNeeded()
        }
    }
    #endif

    #if os(tvOS)
    private var tvControlsOverlay: some View {
        HStack(spacing: 24) {
            VStack(spacing: 16) {
                HStack(spacing: 18) {
                    Button {
                        player.close()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .focused($focusedControl, equals: .close)

                    Button {
                        Task { await toggleFavorite() }
                    } label: {
                        Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
                    }
                    .focused($focusedControl, equals: .favorite)
                    .disabled(player.currentItem == nil)

                    Spacer()

                    if player.isBuffering {
                        Label("Buffering", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                    }
                }

                transportControls
                    .focused($focusedControl, equals: .transport)

                timelineControls

                HStack(spacing: 12) {
                    Button("Media") {
                        tvPanel = .media
                    }
                    .focused($focusedControl, equals: .media)
                    .disabled(!mediaControlsSupported)

                    Button("Quality") {
                        tvPanel = .quality
                    }
                    .focused($focusedControl, equals: .quality)
                    .disabled(!qualityControlsSupported)

                    Button("Chapters") {
                        tvPanel = .chapters
                    }
                    .focused($focusedControl, equals: .chapters)
                    .disabled(!chapterControlsSupported)

                    Button("Settings") {
                        tvPanel = .settings
                    }
                    .focused($focusedControl, equals: .settings)

                    Button("Sleep") {
                        tvPanel = .sleep
                    }
                    .focused($focusedControl, equals: .sleep)

                    Button("Episodes") {
                        tvPanel = .episodes
                    }
                    .focused($focusedControl, equals: .episodes)
                    .disabled(player.episodeOptions.count <= 1)
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
        .background(.black.opacity(0.35))
        .onAppear {
            focusedControl = .transport
        }
    }
    #endif

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
        case .media:
            NavigationStack {
                List {
                    Section("Audio") {
                        audioTrackListRows
                    }
                    Section("Subtitles") {
                        subtitleTrackListRows
                    }
                }
                .navigationTitle("Media")
            }
            .presentationDetents([.medium, .large])

        case .quality:
            NavigationStack {
                List {
                    qualityListRows
                }
                .navigationTitle("Quality")
            }
            .presentationDetents([.medium])

        case .chapters:
            NavigationStack {
                List {
                    chapterListRows
                }
                .navigationTitle("Chapters")
            }
            .presentationDetents([.medium, .large])

        case .settings:
            NavigationStack {
                List {
                    Section("Playback") {
                        speedPicker
                        aspectRatioPicker
                        audioDelayStepper
                    }

                    Section("Quick Settings") {
                        volumeSlider
                        brightnessSlider
                        outputRouteRow
                    }
                }
                .navigationTitle("Quick Settings")
            }
            .presentationDetents([.medium, .large])

        case .sleep:
            NavigationStack {
                List {
                    sleepTimerRows
                }
                .navigationTitle("Sleep Timer")
            }
            .presentationDetents([.medium])

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
        case .media:
            List {
                Section("Audio") {
                    audioTrackListRows
                }
                Section("Subtitles") {
                    subtitleTrackListRows
                }
            }
        case .quality:
            List {
                qualityListRows
            }
        case .chapters:
            List {
                chapterListRows
            }
        case .settings:
            List {
                speedPicker
                aspectRatioPicker
                audioDelayStepper
                volumeSlider
                brightnessSlider
                outputRouteRow
            }
        case .sleep:
            List {
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
            Text("Unsupported by current backend")
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
            Text("Unsupported by current backend")
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
            Text("Quality switching unavailable for this stream")
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
            Text("Chapter navigation unavailable")
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
            ForEach(PlayerAspectRatioMode.allCases) { mode in
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
            Text("Unsupported")
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
            Text("Unsupported")
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
            Text("Unsupported")
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
            Text("Unsupported")
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
            Text("Unsupported")
        }
    }

    private var aspectRatioMenuContent: some View {
        Group {
            ForEach(PlayerAspectRatioMode.allCases) { mode in
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

    private func scheduleAutoHideIfNeeded() {
        hideControlsTask?.cancel()
        guard player.isPlaying else { return }

        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                isShowingControls = false
            }
        }
    }

    private func revealControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
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
    case media
    case quality
    case chapters
    case settings
    case sleep
    case episodes

    var id: String { rawValue }
}
#endif

#if os(tvOS)
private enum TVPanel {
    case media
    case quality
    case chapters
    case settings
    case sleep
    case episodes
}

private enum TVControlFocus: Hashable {
    case close
    case favorite
    case transport
    case media
    case quality
    case chapters
    case settings
    case sleep
    case episodes
}
#endif

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
