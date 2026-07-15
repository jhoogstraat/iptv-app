import CoreGraphics
import Foundation
import Testing

@testable import iptv

struct DetailPresentationTests {
    @Test func enrichmentTransitionsThroughFailureRetryAndSuccess() {
        var state = DetailEnrichmentState.idle

        state.transition(.request)
        #expect(state == .loading)

        state.transition(.failed("The network connection was lost."))
        #expect(state == .failure("The network connection was lost."))

        state.transition(.retry)
        #expect(state == .loading)

        state.transition(.succeeded)
        #expect(state == .success)
    }

    @Test func enrichmentIgnoresCompletionsThatAreNoLongerLoading() {
        var state = DetailEnrichmentState.idle

        state.transition(.succeeded)
        #expect(state == .idle)

        state.transition(.request)
        state.transition(.cancelled)
        state.transition(.failed("Stale failure"))
        #expect(state == .idle)
    }

    @Test func collapsedHeaderProgressMapsAndClampsScrollDistance() {
        #expect(DetailHeroCollapse.progress(heroMinY: 40, collapseDistance: 200) == 0)
        #expect(DetailHeroCollapse.progress(heroMinY: 0, collapseDistance: 200) == 0)
        #expect(DetailHeroCollapse.progress(heroMinY: -50, collapseDistance: 200) == 0.25)
        #expect(DetailHeroCollapse.progress(heroMinY: -200, collapseDistance: 200) == 1)
        #expect(DetailHeroCollapse.progress(heroMinY: -400, collapseDistance: 200) == 1)
        #expect(DetailHeroCollapse.progress(heroMinY: -1, collapseDistance: 0) == 1)
        #expect(DetailHeroCollapse.progress(heroMinY: 1, collapseDistance: 0) == 0)
    }

    @Test func collapsedHeaderAccessibilitySwitchesAtOneStableThreshold() {
        #expect(!DetailHeroCollapse.collapsedHeaderIsAccessible(progress: 0.49))
        #expect(DetailHeroCollapse.collapsedHeaderIsAccessible(progress: 0.5))
    }

    @Test func metadataRowsNormalizeMissingValues() {
        #expect(DetailMetadataRow(label: "Genre", value: nil).displayValue == "Not available")
        #expect(DetailMetadataRow(label: "Genre", value: "  \n ").displayValue == "Not available")
        #expect(DetailMetadataRow(label: "Genre", value: " Drama ").displayValue == "Drama")
    }

    @Test func trailerResolverAcceptsURLsAndYouTubeIdentifiers() {
        #expect(TrailerURLResolver.url(from: nil) == nil)
        #expect(TrailerURLResolver.url(from: "https://example.com/trailer")?.absoluteString == "https://example.com/trailer")
        #expect(TrailerURLResolver.url(from: "abc123")?.absoluteString == "https://www.youtube.com/watch?v=abc123")
    }

    @Test func enrichmentStateWaitsForDetailsUntilTheRequestFinishes() {
        #expect(DetailEnrichmentState.idle.isAwaitingDetails)
        #expect(DetailEnrichmentState.loading.isAwaitingDetails)
        #expect(!DetailEnrichmentState.success.isAwaitingDetails)
        #expect(!DetailEnrichmentState.failure("Unavailable").isAwaitingDetails)
    }
}
