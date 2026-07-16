import SwiftUI
import Observation

@MainActor
@Observable
final class ExternalDisplayRuntimeBridge {
    static let shared = ExternalDisplayRuntimeBridge()
    private(set) var runtime: ApplicationRuntime?

    private init() {}

    func install(_ runtime: ApplicationRuntime) {
        self.runtime = runtime
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

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = UIHostingController(
            rootView: ExternalDisplayBootstrapView(sceneID: sceneID)
        )
        window.makeKeyAndVisible()
        self.window = window

        ExternalDisplayRuntimeBridge.shared.runtime?.playbackDestinationCoordinator
            .externalSceneConnected(id: sceneID, name: "External Display")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let sceneID else { return }
        ExternalDisplayRuntimeBridge.shared.runtime?.playbackDestinationCoordinator
            .externalSceneDisconnected(id: sceneID)
        window?.rootViewController = nil
        window = nil
        self.sceneID = nil
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
