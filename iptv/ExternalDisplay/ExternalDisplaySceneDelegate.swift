import SwiftUI
import Observation

@MainActor
@Observable
final class ExternalDisplayRuntimeBridge {
    static let shared = ExternalDisplayRuntimeBridge()
    private(set) var runtime: ApplicationRuntime?
    @ObservationIgnored
    private var connectedScenes: [String: String] = [:]

    init() {}

    func install(_ runtime: ApplicationRuntime) {
        self.runtime = runtime
        replayConnections(to: runtime.playbackDestinationCoordinator)
    }

    func externalSceneConnected(id: String, name: String) {
        connectedScenes[id] = name
        runtime?.playbackDestinationCoordinator.externalSceneConnected(id: id, name: name)
    }

    func externalSceneDisconnected(id: String) {
        connectedScenes.removeValue(forKey: id)
        runtime?.playbackDestinationCoordinator.externalSceneDisconnected(id: id)
    }

    func replayConnections(to coordinator: PlaybackDestinationCoordinator) {
        for (id, name) in connectedScenes {
            coordinator.externalSceneConnected(id: id, name: name)
        }
    }
}

#if os(iOS)
import UIKit

final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var sceneID: String?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let sceneID = session.persistentIdentifier
        self.sceneID = sceneID

        configure(screen: windowScene.screen)

        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.screen.bounds
        window.backgroundColor = .black
        let hostingController = UIHostingController(
            rootView: ExternalDisplayBootstrapView(sceneID: sceneID)
        )
        hostingController.view.backgroundColor = .black
        hostingController.view.frame = window.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.view.insetsLayoutMarginsFromSafeArea = false
        hostingController.viewRespectsSystemMinimumLayoutMargins = false
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        self.window = window

        ExternalDisplayRuntimeBridge.shared.externalSceneConnected(
            id: sceneID,
            name: "External Display"
        )
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let sceneID else { return }
        ExternalDisplayRuntimeBridge.shared.externalSceneDisconnected(id: sceneID)
        window?.rootViewController = nil
        window = nil
        self.sceneID = nil
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: any UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        window?.frame = windowScene.screen.bounds
        window?.rootViewController?.view.frame = windowScene.screen.bounds
    }

    private func configure(screen: UIScreen) {
        // UIKit defaults to scaling external output inward for televisions that
        // report overscan. The playback scene intentionally uses the complete
        // framebuffer; users can still choose Fit or Fill for source aspect.
        screen.currentMode = screen.preferredMode
        screen.overscanCompensation = .none
    }
}

private struct ExternalDisplayBootstrapView: View {
    let sceneID: String

    var body: some View {
        if let runtime = ExternalDisplayRuntimeBridge.shared.runtime {
            ExternalDisplayView(sceneID: sceneID)
                .environment(runtime.player)
                .environment(runtime.playbackDestinationCoordinator)
        } else {
            ExternalDisplayReadyView(message: "Open iptv on your device to begin.")
        }
    }
}
#endif
