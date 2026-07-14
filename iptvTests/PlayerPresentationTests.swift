import Testing

@testable import iptv

@MainActor
struct PlayerPresentationTests {
    @Test func episodePlaybackRequestsFullWindowPlayer() {
        #expect(EpisodeDetailTile.playbackPresentation == .fullWindow)
    }

    @Test func seriesEpisodeSelectionRequestsFullWindowPlayer() {
        #expect(SeriesDetailScreen.episodePlaybackPresentation == .fullWindow)
    }

    @Test func windowPresentationTransitionOpensAndDismissesPlayer() {
        #expect(PlayerWindowPresentationAction.action(from: .inline, to: .fullWindow) == .open)
        #expect(PlayerWindowPresentationAction.action(from: .fullWindow, to: .inline) == .dismiss)
        #expect(PlayerWindowPresentationAction.action(from: .inline, to: .inline) == .none)
        #expect(PlayerWindowPresentationAction.action(from: .fullWindow, to: .fullWindow) == .none)
    }

    @Test func presentationLifecycleConsumesCleanupExactlyOnce() {
        var lifecycle = PlayerPresentationLifecycle()

        #expect(lifecycle.consumeResetOnDisappear(hasLoadedItem: false) == false)
        #expect(lifecycle.consumeResetOnDisappear(hasLoadedItem: true) == true)
        #expect(lifecycle.consumeResetOnDisappear(hasLoadedItem: true) == false)
    }

    @Test func tvBackTraversesPanelControlsAndPlayerHierarchy() {
        var isPanelPresented = true
        var areControlsVisible = true

        #expect(TVPlayerExitAction.action(
            isPanelPresented: isPanelPresented,
            areControlsVisible: areControlsVisible
        ) == .dismissPanel)

        isPanelPresented = false
        #expect(TVPlayerExitAction.action(
            isPanelPresented: isPanelPresented,
            areControlsVisible: areControlsVisible
        ) == .hideControls)

        areControlsVisible = false
        #expect(TVPlayerExitAction.action(
            isPanelPresented: isPanelPresented,
            areControlsVisible: areControlsVisible
        ) == .closePlayer)
    }

    @Test func controlsDoNotAutoHideDuringInteraction() {
        let cases = [
            (assistive: true, focus: false, panel: false, scrubbing: false),
            (assistive: false, focus: true, panel: false, scrubbing: false),
            (assistive: false, focus: false, panel: true, scrubbing: false),
            (assistive: false, focus: false, panel: false, scrubbing: true),
        ]

        for testCase in cases {
            #expect(PlayerControlsAutoHidePolicy.shouldAutoHide(
                isPlaying: true,
                isAssistiveInteractionActive: testCase.assistive,
                isFocusInteractionActive: testCase.focus,
                isPanelPresented: testCase.panel,
                isScrubbing: testCase.scrubbing
            ) == false)
        }
    }

    @Test func controlsAutoHideOnlyDuringUninterruptedPlayback() {
        #expect(PlayerControlsAutoHidePolicy.shouldAutoHide(
            isPlaying: true,
            isAssistiveInteractionActive: false,
            isFocusInteractionActive: false,
            isPanelPresented: false,
            isScrubbing: false
        ))
        #expect(PlayerControlsAutoHidePolicy.shouldAutoHide(
            isPlaying: false,
            isAssistiveInteractionActive: false,
            isFocusInteractionActive: false,
            isPanelPresented: false,
            isScrubbing: false
        ) == false)
    }
}
