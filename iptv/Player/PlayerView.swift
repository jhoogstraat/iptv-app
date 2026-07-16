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
    @Environment(PlaybackDestinationCoordinator.self) private var destinationCoordinator
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled
    @AppStorage(FavoriteStore.revisionKey) private var favoritesRevision = 0

    @State private var isShowingControls = true
    @State private var scrubTime: Double?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var bufferingHUDTask: Task<Void, Never>?
    @State private var controlMessageHUDTask: Task<Void, Never>?
    @State private var isShowingBufferingHUD = false

    #if os(iOS) || os(visionOS)
    @State private var mobileSheet: PlayerPanel?
    #endif

    #if os(iOS)
    @State private var iOSScrubSession: IOSScrubSession?
    #endif

    #if os(tvOS)
    @State private var tvPanel: PlayerPanel?
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

    private var isPanelPresented: Bool {
        #if os(tvOS)
        tvPanel != nil
        #elseif os(iOS) || os(visionOS)
        mobileSheet != nil
        #else
        false
        #endif
    }

    private var isFocusInteractionActive: Bool {
        #if os(tvOS)
        focusedControl != nil
        #else
        false
        #endif
    }
    
    private var eyebrowText: String? {
        guard let item = player.currentItem else { return nil }

        switch item.type {
        case .movie:
            return "Movie"
        case .series:
            return "Series"
        case .episode:
            return "Episode"
        case .live:
            return "Live"
        }
    }

    private var synopsisText: String? {
        guard !player.isPlaying else { return nil }
        guard let synopsis = player.currentItem?.synopsis?.trimmingCharacters(in: .whitespacesAndNewlines),
              !synopsis.isEmpty
        else { return nil }
        return synopsis
    }

    private var displayTitle: String {
        player.currentItem?.title ?? "No item loaded"
    }

    private var isLiveStream: Bool {
        player.currentItem?.type == .live && !player.isCatchupPlayback
    }

    private var primaryTransportTitle: String {
        if player.isPlaybackComplete {
            return "Replay"
        }
        return player.isPlaying ? "Pause" : "Play"
    }

    private var primaryTransportSystemImage: String {
        if player.isPlaybackComplete {
            return "arrow.counterclockwise"
        }
        return player.isPlaying ? "pause.fill" : "play.fill"
    }

    private var primaryTransportValue: String {
        if player.isPlaybackComplete {
            return "Playback finished"
        }
        return player.isPlaying ? "Playing" : "Paused"
    }

    private var controlsFadeAnimation: Animation {
        .easeInOut(duration: 0.28)
    }

    private var shouldShowPersistentControlsLauncher: Bool {
        #if os(tvOS) || os(macOS)
        true
        #else
        false
        #endif
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
            } else if shouldShowPersistentControlsLauncher {
                showControlsButton
                    .transition(.opacity)
            }

            playbackStateHUD
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            scheduleAutoHideIfNeeded()
            updateBufferingHUD(isBuffering: player.isBuffering)
            player.refreshOutputRoutes()
        }
        .onChange(of: player.isPlaying) { _, _ in
            scheduleAutoHideIfNeeded()
        }
        .onChange(of: player.isBuffering) { _, isBuffering in
            updateBufferingHUD(isBuffering: isBuffering)
        }
        .onChange(of: isVoiceOverEnabled) { _, _ in
            scheduleAutoHideIfNeeded()
        }
        .onChange(of: isSwitchControlEnabled) { _, _ in
            scheduleAutoHideIfNeeded()
        }
        .onChange(of: player.activeBackendID) { _, _ in
            player.refreshOutputRoutes()
        }
        .onChange(of: player.currentItem?.id) { _, _ in
            player.refreshOutputRoutes()
        }
        .onChange(of: player.errorMessage) { _, message in
            guard isVoiceOverEnabled, let message else { return }
            AccessibilityNotification.Announcement("Playback error. \(message)").post()
        }
        .onChange(of: player.controlMessage) { _, message in
            guard isVoiceOverEnabled, let message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
        .onChange(of: player.controlMessage) { _, message in
            scheduleControlMessageDismissal(message)
        }
        #if os(iOS) || os(tvOS)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            #if os(iOS)
            player.systemOutputRouteDidChange()
            #else
            player.refreshOutputRoutes()
            #endif
        }
        #endif
        .onDisappear {
            hideControlsTask?.cancel()
            bufferingHUDTask?.cancel()
            controlMessageHUDTask?.cancel()
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
            handleTVExit()
        }
        .onChange(of: focusedControl) { _, _ in
            scheduleAutoHideIfNeeded()
        }
        .onChange(of: tvPanel) { _, _ in
            scheduleAutoHideIfNeeded()
        }
        #endif
        #if os(iOS) || os(visionOS)
        .sheet(item: $mobileSheet, onDismiss: scheduleAutoHideIfNeeded) { sheet in
            mobileSheetView(sheet)
        }
        .onChange(of: mobileSheet) { _, _ in
            scheduleAutoHideIfNeeded()
        }
        #endif
        .accessibilityAction(named: "Show Controls") {
            revealControls()
        }
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
                Task {
                    await player.closeAndFlush()
                }
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.headline.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            #if os(visionOS)
            .buttonStyle(.bordered)
            #else
            .buttonStyle(.plain)
            .glassEffect(.clear.interactive(), in: Circle())
            #endif
            .buttonBorderShape(.circle)
            #if os(tvOS)
            .focused($focusedControl, equals: .close)
            #endif
            .accessibilityLabel("Close Player")
            .accessibilityHint("Stops playback and returns to the previous screen.")
            .accessibilityIdentifier("player.close")

            Spacer()
        }
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                .accessibilityAddTraits(.isHeader)

            if let synopsisText {
                Text(synopsisText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: player.isPlaying)
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
            if !isLiveStream {
                Button {
                    scrubTime = nil
                    player.seek(by: -10)
                } label: {
                    Image(systemName: "10.arrow.trianglehead.counterclockwise")
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(.clear.interactive(), in: Circle())
                .accessibilityLabel("Seek backward 10 seconds")
                .accessibilityValue(player.formattedCurrentTime)
                .accessibilityIdentifier("player.seekBack")
                #if os(tvOS)
                .focused($focusedControl, equals: .seekBackward)
                #elseif os(macOS)
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                #endif
            }

            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: primaryTransportSystemImage)
                    .font(.title2.weight(.semibold))
                    .frame(width: 58, height: 58)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Color.accentColor).interactive(), in: Circle())
            .accessibilityLabel(primaryTransportTitle)
            .accessibilityValue(primaryTransportValue)
            .accessibilityIdentifier("player.playPause")
            #if os(tvOS)
            .focused($focusedControl, equals: .playPause)
            #elseif os(macOS)
            .keyboardShortcut(.space, modifiers: [])
            #endif

            if !isLiveStream {
                Button {
                    scrubTime = nil
                    player.seek(by: 10)
                } label: {
                    Image(systemName: "10.arrow.trianglehead.clockwise")
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(.clear.interactive(), in: Circle())
                .accessibilityLabel("Seek forward 10 seconds")
                .accessibilityValue(player.formattedCurrentTime)
                .accessibilityIdentifier("player.seekForward")
                #if os(tvOS)
                .focused($focusedControl, equals: .seekForward)
                #elseif os(macOS)
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                #endif
            }
        }
        .font(.title2)
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    private var timelineControls: some View {
        VStack(spacing: 8) {
            if isLiveStream {
                HStack(spacing: 12) {
                    Button {
                        player.zapLiveChannel(by: -1)
                    } label: {
                        Label("Previous Channel", systemImage: "backward.end.fill")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(player.liveChannelQueue.count < 2)

                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)

                    Button {
                        player.zapLiveChannel(by: 1)
                    } label: {
                        Label("Next Channel", systemImage: "forward.end.fill")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(player.liveChannelQueue.count < 2)

                    Spacer()
                    Text("Basic live stream · DVR unavailable")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityIdentifier("player.liveTimelineUnavailable")
            } else {
                #if os(iOS)
                iOSTimelineScrubber
                #elseif os(tvOS)
                ProgressView(value: player.progressFraction)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(player.formattedCurrentTime) of \(player.formattedDuration)")
                    .accessibilityIdentifier("player.timeline")
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
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(player.formattedCurrentTime) of \(player.formattedDuration)")
                #endif

                HStack {
                    Text(player.formattedCurrentTime)
                    Spacer()
                    Text(player.formattedRemainingTime)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
            }
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

                if let scrubTime {
                    Text(formatTime(scrubTime))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: Capsule())
                        .fixedSize()
                        .position(
                            x: min(max(proxy.size.width * fraction, 34), max(proxy.size.width - 34, 34)),
                            y: 10
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
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
                    player.seek(by: delta)
                case .decrement:
                    player.seek(by: -delta)
                @unknown default:
                    break
                }
            }
        }
        .frame(height: scrubTime == nil ? 44 : 70)
        .animation(.easeInOut(duration: 0.16), value: scrubTime != nil)
    }
    #endif

    #if os(iOS) || os(visionOS)
    private var mobileControlsOverlay: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, proxy.safeAreaInsets.top + 16)

                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    infoPanel

                    timelineControls

                    transportStrip

                    mobileActionControls(availableWidth: max(proxy.size.width - 40, 0))

                    if player.outputRoutes.count > 1 {
                        outputRouteSummary
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                    Spacer(minLength: 0)

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

                HStack(spacing: 12) {
                    favoriteControlButton
                        .focused($focusedControl, equals: .favorite)

                    Button("Languages") {
                        presentTVPanel(.languages)
                    }
                    .frame(minHeight: 44)
                    .focused($focusedControl, equals: .languages)

                    Button("Settings") {
                        presentTVPanel(.settings)
                    }
                    .frame(minHeight: 44)
                    .focused($focusedControl, equals: .settings)


                }

                if player.outputRoutes.count > 1 {
                    outputRouteSummary
                }
            }

            if let panel = tvPanel {
                tvPanelView(panel)
                    .frame(width: 360)
                    .padding(18)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .focusSection()
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(panel.title) panel")
            }
        }
        .padding(28)
        .foregroundStyle(.white)
        .onAppear {
            focusedControl = .playPause
        }
    }
    #endif

    private var transportStrip: some View {
        GlassEffectContainer(spacing: 14) {
            transportControls
                .font(.title2)
        }
    }

    private var favoriteControlButton: some View {
        let isFavorite = currentItemIsFavorite

        return Button {
            guard let item = player.currentItem, let providerID = player.currentProviderID else { return }
            do {
                let result = try FavoriteStore.toggle(item, providerID: providerID)
                switch result {
                case .added:
                    player.reportControlMessage("Added to Favorites.")
                case .removed:
                    player.reportControlMessage("Removed from Favorites.")
                }
            } catch {
                player.reportControlMessage("Could not update Favorites. \(error.localizedDescription)")
            }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.headline.weight(.semibold))
                .foregroundStyle(isFavorite ? .red : .white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isFavorite
                ? .regular.tint(.red).interactive()
                : .clear.interactive(),
            in: Circle()
        )
        .disabled(player.currentItem == nil || player.currentProviderID == nil)
        .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityHint("Updates the persisted favorite state for the current provider.")
        .accessibilityIdentifier(isFavorite ? "player.favoriteSelected" : "player.favorite")
    }

    private var currentItemIsFavorite: Bool {
        _ = favoritesRevision
        guard let item = player.currentItem else { return false }
        return FavoriteStore.isFavorite(item, providerID: player.currentProviderID)
    }

    #if os(iOS) || os(visionOS)
    @ViewBuilder
    private func mobileActionControls(availableWidth: CGFloat) -> some View {
        if availableWidth < 430 {
            compactMobileActionRow
        } else {
            mobileControlChipRow
        }
    }

    private var mobileControlChipRow: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                favoriteControlButton
                languagesControlChip
                chaptersControlChip
                settingsControlChip
                #if os(iOS)
                outputRouteGlassButton
                #endif
            }
        }
    }

    private var compactMobileActionRow: some View {
        HStack(alignment: .center, spacing: 10) {
            favoriteControlButton

            compactMobileControlGroup {
                compactIconControlButton(
                    systemImage: "captions.bubble",
                    accessibilityLabel: "Languages",
                    accessibilityIdentifier: "player.chip.languages"
                ) {
                    mobileSheet = .languages
                }

                if !player.chapterMarkers.isEmpty {
                    compactIconControlButton(
                        systemImage: "list.number",
                        accessibilityLabel: "Chapters",
                        accessibilityIdentifier: "player.chip.chapters"
                    ) {
                        mobileSheet = .chapters
                    }
                }

                compactIconControlButton(
                    systemImage: "gearshape",
                    accessibilityLabel: "Playback Settings",
                    accessibilityIdentifier: "player.chip.settings"
                ) {
                    mobileSheet = .settings
                }
            }

#if os(iOS)
            outputRouteGlassButton
#endif
            Spacer(minLength: 0)
        }
    }

    private var languagesControlChip: some View {
        controlChip("Languages", icon: "captions.bubble") {
            mobileSheet = .languages
        }
        .accessibilityIdentifier("player.chip.languages")
    }

    @ViewBuilder
    private var chaptersControlChip: some View {
        if !player.chapterMarkers.isEmpty {
            controlChip("Chapters", icon: "list.number") {
                mobileSheet = .chapters
            }
            .accessibilityIdentifier("player.chip.chapters")
        }
    }

    private var settingsControlChip: some View {
        controlChip("Settings", icon: "gearshape") {
            mobileSheet = .settings
        }
        .accessibilityIdentifier("player.chip.settings")
    }

    #if os(iOS)
    private var outputRouteGlassButton: some View {
        OutputRoutePickerButton()
            .frame(width: 44, height: 44)
            .glassEffect(.clear.interactive(), in: Circle())
            .disabled(!player.capabilities.supportsOutputRouteSelection)
            .accessibilityLabel("AirPlay and output device")
    }
    #endif
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

    private var showControlsButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    revealControls()
                } label: {
                    Label("Show Controls", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .glassEffect(.clear.interactive(), in: Capsule())
                #if os(tvOS)
                .focused($focusedControl, equals: .showControls)
                #endif
                .accessibilityHint("Reveals playback, timeline, and player options.")
                .accessibilityIdentifier("player.showControls")
            }
        }
        .padding(24)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var playbackStateHUD: some View {
        if let errorMessage = player.errorMessage {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)

                Text("Playback Unavailable")
                    .font(.headline)

                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button("Close") {
                        Task {
                            await player.closeAndFlush()
                        }
                    }
                    .buttonStyle(.glass)

                    Button("Try Again") {
                        player.retryCurrentItem()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                    .accessibilityIdentifier("player.retry")
                }
            }
            .padding(22)
            .frame(maxWidth: 360)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Playback error. \(errorMessage)")
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else if isShowingBufferingHUD {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.large)
                Text("Reconnecting…")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .glassEffect(.regular, in: Capsule())
            .accessibilityLabel("Playback is buffering")
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else if let controlMessage = player.controlMessage {
            Text(controlMessage)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: Capsule())
                .padding(24)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .allowsHitTesting(false)
        }
    }

    private var overlayBackground: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .black.opacity(0.5),
                    .black.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [
                    .black.opacity(0),
                    .black.opacity(0.34),
                    .black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxHeight: 480)
        }
    }

    #if os(iOS) || os(visionOS)
    private func controlChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: Capsule())
    }

    private func compactMobileControlGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 14) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.clear.interactive(), in: Capsule())
    }

    private func compactIconControlButton(
        systemImage: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
    #endif

    #if os(iOS) || os(visionOS)
    @ViewBuilder
    private func mobileSheetView(_ sheet: PlayerPanel) -> some View {
        switch sheet {
        case .languages:
            NavigationStack {
                List {
                    Section("Audio") {
                        audioTrackListRows
                    }
                    Section("Subtitles") {
                        subtitleTrackListRows
                    }
                }
                .navigationTitle("Languages")
            }
            .presentationDetents([.medium, .large])

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
                        if isLiveStream {
                            Text("Playback speed, seeking, catch-up, and DVR controls are unavailable for live channels.")
                                .foregroundStyle(.secondary)
                            aspectRatioPicker
                        } else {
                            speedPicker
                            aspectRatioPicker
                            audioDelayStepper
                        }
                    }

                    Section("Quality") {
                        qualityListRows
                    }

                    Section("Display") {
                        volumeSlider
                        brightnessSlider
                    }

                    destinationSections

                    Section("Sleep Timer") {
                        sleepTimerRows
                    }
                }
                .navigationTitle("Playback Settings")
            }
            .presentationDetents([.medium, .large])

        }
    }
    #endif

    #if os(tvOS)
    private func tvPanelView(_ panel: PlayerPanel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(panel.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close Panel") {
                    dismissTVPanel()
                }
                .focused($focusedControl, equals: .panelClose)
            }

            switch panel {
            case .languages:
                List {
                    Section("Audio") {
                        audioTrackListRows
                    }
                    Section("Subtitles") {
                        subtitleTrackListRows
                    }
                }
            case .chapters:
                List {
                    chapterListRows
                }
            case .settings:
                List {
                    if isLiveStream {
                        Text("Playback speed, seeking, catch-up, and DVR controls are unavailable for live channels.")
                        aspectRatioPicker
                    } else {
                        speedPicker
                        aspectRatioPicker
                        audioDelayStepper
                    }
                    volumeSlider
                    brightnessSlider
                    destinationSections
                    sleepTimerRows
                }
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
        #if os(tvOS)
        Text("Audio delay is not available from the tvOS player controls.")
            .foregroundStyle(.secondary)
        #else
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
        #endif
    }

    private var volumeSlider: some View {
        #if os(tvOS)
        Text("Volume is controlled with the Siri Remote or system output device.")
            .foregroundStyle(.secondary)
        #else
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
        #endif
    }

    @ViewBuilder
    private var brightnessSlider: some View {
        #if os(tvOS)
        Text("Brightness is controlled by the TV or display settings.")
            .foregroundStyle(.secondary)
        #else
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
        #endif
    }

    @ViewBuilder
    private var outputRouteRow: some View {
        #if os(iOS) || os(tvOS)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output Device")
                Spacer()
                if let activeRoute = player.outputRoutes.first(where: { $0.isActive }) {
                    Text(activeRoute.name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
    private var destinationSections: some View {
        Section("Playback Destination") {
            ForEach(destinationCoordinator.availableDestinations) { destination in
                Button {
                    player.movePlayback(to: destination)
                    #if os(iOS) || os(visionOS)
                    mobileSheet = nil
                    #endif
                } label: {
                    HStack {
                        Image(systemName: destination.kind == .device ? "iphone" : "display")
                        Text(destination.name)
                        Spacer()
                        if destination.id == destinationCoordinator.selectedDestination.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityValue(destination.id == destinationCoordinator.selectedDestination.id ? "Selected" : "")
            }
        }

        Section("System Audio & AirPlay") {
            outputRouteRow
        }
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

            if isLiveStream {
                Text("Speed, seeking, catch-up, and DVR unavailable for live channels")
            } else {
                Menu("Speed") {
                    speedMenuContent
                }
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
        guard PlayerControlsAutoHidePolicy.shouldAutoHide(
            isPlaying: player.isPlaying,
            isAssistiveInteractionActive: isVoiceOverEnabled || isSwitchControlEnabled,
            isFocusInteractionActive: isFocusInteractionActive,
            isPanelPresented: isPanelPresented,
            isScrubbing: scrubTime != nil
        ) else { return }

        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            guard PlayerControlsAutoHidePolicy.shouldAutoHide(
                isPlaying: player.isPlaying,
                isAssistiveInteractionActive: isVoiceOverEnabled || isSwitchControlEnabled,
                isFocusInteractionActive: isFocusInteractionActive,
                isPanelPresented: isPanelPresented,
                isScrubbing: scrubTime != nil
            ) else { return }
            hideControls()
        }
    }

    private func updateBufferingHUD(isBuffering: Bool) {
        bufferingHUDTask?.cancel()

        guard isBuffering else {
            withAnimation(.easeOut(duration: 0.16)) {
                isShowingBufferingHUD = false
            }
            return
        }

        bufferingHUDTask = Task {
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, player.isBuffering else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                isShowingBufferingHUD = true
            }
        }
    }

    private func scheduleControlMessageDismissal(_ message: String?) {
        controlMessageHUDTask?.cancel()
        guard message != nil else { return }

        controlMessageHUDTask = Task {
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                player.clearControlMessage()
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
        guard !isPanelPresented else { return }
        hideControlsTask?.cancel()
        withAnimation(controlsFadeAnimation) {
            isShowingControls = false
        }
        #if os(tvOS)
        focusedControl = .showControls
        #endif
    }

    private func revealControls() {
        withAnimation(controlsFadeAnimation) {
            isShowingControls = true
        }
        #if os(tvOS)
        focusedControl = .playPause
        #endif
        scheduleAutoHideIfNeeded()
    }

    #if os(tvOS)
    private func presentTVPanel(_ panel: PlayerPanel) {
        hideControlsTask?.cancel()
        tvPanel = panel
        focusedControl = .panelClose
    }

    private func dismissTVPanel() {
        guard let panel = tvPanel else { return }
        tvPanel = nil
        focusedControl = panel.tvLauncherFocus
    }

    private func handleTVExit() {
        switch TVPlayerExitAction.action(
            isPanelPresented: tvPanel != nil,
            areControlsVisible: isShowingControls
        ) {
        case .dismissPanel:
            dismissTVPanel()
        case .hideControls:
            hideControls()
        case .closePlayer:
            Task {
                await player.closeAndFlush()
            }
        }
    }
    #endif



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
        let speedMultiplier = IOSScrubPrecisionPolicy.multiplier(forVerticalDistance: verticalDistance)
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

private enum PlayerPanel: String, Identifiable {
    case languages
    case chapters
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .languages: "Languages"
        case .chapters: "Chapters"
        case .settings: "Playback Settings"
        }
    }
}

#if os(iOS)
private struct IOSScrubSession {
    let anchorTime: Double
    let anchorLocation: CGPoint
    let trackWidth: CGFloat
    let trackCenterY: CGFloat
}
#endif



#if os(tvOS)
private enum TVControlFocus: Hashable {
    case close
    case seekBackward
    case playPause
    case seekForward
    case favorite
    case languages
    case chapters
    case settings
    case panelClose
    case showControls
}

private extension PlayerPanel {
    var tvLauncherFocus: TVControlFocus {
        switch self {
        case .languages: .languages
        case .chapters: .chapters
        case .settings: .settings
        }
    }
}
#endif

struct PlayerControlsAutoHidePolicy {
    static func shouldAutoHide(
        isPlaying: Bool,
        isAssistiveInteractionActive: Bool,
        isFocusInteractionActive: Bool,
        isPanelPresented: Bool,
        isScrubbing: Bool
    ) -> Bool {
        isPlaying
            && !isAssistiveInteractionActive
            && !isFocusInteractionActive
            && !isPanelPresented
            && !isScrubbing
    }
}

enum TVPlayerExitAction: Equatable {
    case dismissPanel
    case hideControls
    case closePlayer

    static func action(isPanelPresented: Bool, areControlsVisible: Bool) -> Self {
        if isPanelPresented {
            return .dismissPanel
        }
        if areControlsVisible {
            return .hideControls
        }
        return .closePlayer
    }
}

#if os(iOS)
struct IOSScrubPrecisionPolicy {
    static func multiplier(forVerticalDistance distance: CGFloat) -> Double {
        let normalized = min(max(distance / 36, 0), 5)
        return 1 / (1 + Double(normalized * 1.4))
    }
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

#Preview {
    PlayerView()
}
