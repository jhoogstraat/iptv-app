import Foundation
import Testing

@testable import iptv

@MainActor
struct PlaybackDestinationCoordinatorTests {
    @Test func rendererArbiterReplacesOneHostAtATime() {
        var arbiter = RendererHostArbiter()
        #expect(arbiter.selectedHost == .device)
        let didSelectOne = arbiter.select(.externalScene("one"))
        #expect(didSelectOne)
        #expect(arbiter.selectedHost == .externalScene("one"))
        let didSelectTwo = arbiter.select(.externalScene("two"))
        #expect(didSelectTwo)
        #expect(arbiter.selectedHost == .externalScene("two"))
        let didRepeatSelection = arbiter.select(.externalScene("two"))
        #expect(didRepeatSelection == false)
    }

    @Test func disconnectOnlyDetachesMatchingExternalHost() {
        var arbiter = RendererHostArbiter()
        arbiter.select(.externalScene("active"))
        let didDetachStaleHost = arbiter.disconnectExternalScene(id: "stale")
        #expect(didDetachStaleHost == false)
        #expect(arbiter.selectedHost == .externalScene("active"))
        let didDetachActiveHost = arbiter.disconnectExternalScene(id: "active")
        #expect(didDetachActiveHost)
        #expect(arbiter.selectedHost == nil)
    }

    @Test func repeatedSceneNotificationsDoNotDuplicateDestinations() {
        let coordinator = PlaybackDestinationCoordinator()
        coordinator.externalSceneConnected(id: "screen", name: "HDMI Display")
        coordinator.externalSceneConnected(id: "screen", name: "HDMI Display")
        #expect(coordinator.availableDestinations.filter { $0.kind == .wiredDisplay }.count == 1)

        coordinator.externalSceneDisconnected(id: "screen")
        coordinator.externalSceneDisconnected(id: "screen")
        #expect(coordinator.availableDestinations == [.device])
    }

    @Test func staleRendererTeardownCannotDetachReplacementOwner() {
        let deviceOwner = UUID()
        let displayOwner = UUID()
        var owner = RendererAttachmentOwner()

        owner.claim(deviceOwner)
        owner.claim(displayOwner)
        let staleReleaseSucceeded = owner.release(deviceOwner)

        #expect(staleReleaseSucceeded == false)
        #expect(owner.ownerID == displayOwner)
        let activeReleaseSucceeded = owner.release(displayOwner)
        #expect(activeReleaseSucceeded)
        #expect(owner.ownerID == nil)
    }
}
