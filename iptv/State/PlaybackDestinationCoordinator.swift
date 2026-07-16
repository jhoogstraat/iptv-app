import Foundation
import Observation
import OSLog

enum PlaybackDestinationKind: String, Sendable {
    case device
    case wiredDisplay
    case airPlay
}

enum PlaybackDestinationConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(String)

    var accessibilityLabel: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting"
        case .failed: "Connection failed"
        }
    }
}

struct PlaybackDestinationCapabilities: Equatable, Sendable {
    var supportsSeek: Bool
    var supportsTracks: Bool
    var supportsSubtitles: Bool
    var supportsRate: Bool
    var supportsVolume: Bool
    var supportsLiveStreams: Bool

    static let local = Self(
        supportsSeek: true,
        supportsTracks: true,
        supportsSubtitles: true,
        supportsRate: true,
        supportsVolume: true,
        supportsLiveStreams: true
    )

    static let nativeAirPlay = Self(
        supportsSeek: true,
        supportsTracks: true,
        supportsSubtitles: true,
        supportsRate: false,
        supportsVolume: true,
        supportsLiveStreams: true
    )
}

struct PlaybackDestination: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: PlaybackDestinationKind
    let capabilities: PlaybackDestinationCapabilities

    static let device = Self(
        id: "device",
        name: "This Device",
        kind: .device,
        capabilities: .local
    )
}

enum PlayerRendererHost: Hashable, Sendable {
    case device
    case externalScene(String)
}

struct RendererHostArbiter: Equatable, Sendable {
    private(set) var selectedHost: PlayerRendererHost? = .device

    @discardableResult
    mutating func select(_ host: PlayerRendererHost?) -> Bool {
        guard selectedHost != host else { return false }
        selectedHost = host
        return true
    }

    @discardableResult
    mutating func disconnectExternalScene(id: String) -> Bool {
        guard selectedHost == .externalScene(id) else { return false }
        selectedHost = nil
        return true
    }
}

private let destinationLogger = Logger(subsystem: "IPTV", category: "PlaybackDestination")

@MainActor
@Observable
final class PlaybackDestinationCoordinator {
    private(set) var availableDestinations: [PlaybackDestination] = [.device]
    private(set) var selectedDestination: PlaybackDestination = .device
    private(set) var connectionState: PlaybackDestinationConnectionState = .connected
    private(set) var rendererHost: PlayerRendererHost? = .device
    private(set) var needsLocalContinuation = false
    private(set) var isAVExternalPlaybackActive = false

    @ObservationIgnored
    private weak var player: Player?
    @ObservationIgnored
    private var hostArbiter = RendererHostArbiter()
    @ObservationIgnored
    private var sceneDestinations: [String: PlaybackDestination] = [:]

    var isPlayingOffDevice: Bool {
        selectedDestination.kind != .device && player?.currentItem != nil
    }

    var selectedDestinationName: String { selectedDestination.name }

    func bind(player: Player) {
        self.player = player
        player.bind(destinationCoordinator: self)
    }

    func rendererIsOwned(by host: PlayerRendererHost) -> Bool {
        rendererHost == host
    }

    func externalSceneConnected(id: String, name: String) {
        let destination = PlaybackDestination(
            id: "wired:\(id)",
            name: name.isEmpty ? "External Display" : name,
            kind: .wiredDisplay,
            capabilities: .local
        )
        sceneDestinations[id] = destination
        rebuildAvailableDestinations()
        destinationLogger.info("Destination connected kind=wired")

        if selectedDestination.id == destination.id {
            connectionState = .connected
            selectRendererHost(.externalScene(id))
        }
    }

    func externalSceneDisconnected(id: String) {
        guard let destination = sceneDestinations.removeValue(forKey: id) else { return }
        rebuildAvailableDestinations()
        let wasSelected = selectedDestination.id == destination.id
        if hostArbiter.disconnectExternalScene(id: id) {
            rendererHost = hostArbiter.selectedHost
        }
        guard wasSelected else { return }

        player?.pauseForDestinationLoss()
        connectionState = .disconnected
        needsLocalContinuation = true
        destinationLogger.info("Destination disconnected kind=wired result=paused")
    }

    func requestSelection(_ destination: PlaybackDestination) {
        switch destination.kind {
        case .device:
            requestDevicePlayback(autoplay: player?.isPlaying == true)
        case .wiredDisplay:
            guard let sceneID = sceneDestinations.first(where: { $0.value.id == destination.id })?.key else {
                connectionState = .failed("The display is no longer available.")
                return
            }
            let autoplay = player?.isPlaying == true
            connectionState = .connecting
            selectedDestination = destination
            needsLocalContinuation = false
            selectRendererHost(.externalScene(sceneID))
            connectionState = .connected
            player?.completeRendererHandoff(autoplay: autoplay)
            destinationLogger.info("Destination transition kind=wired result=connected")
        case .airPlay:
            selectedDestination = destination
            connectionState = .connected
            needsLocalContinuation = false
            selectRendererHost(nil)
        }
    }

    func continueOnDevice() {
        requestDevicePlayback(autoplay: false)
    }

    func avExternalPlaybackChanged(isActive: Bool, routeName: String? = nil) {
        guard isAVExternalPlaybackActive != isActive else { return }
        isAVExternalPlaybackActive = isActive

        if isActive {
            let destination = PlaybackDestination(
                id: "airplay",
                name: routeName?.isEmpty == false ? routeName! : "AirPlay",
                kind: .airPlay,
                capabilities: .nativeAirPlay
            )
            availableDestinations.removeAll { $0.kind == .airPlay }
            availableDestinations.append(destination)
            selectedDestination = destination
            connectionState = .connected
            needsLocalContinuation = false
            selectRendererHost(nil)
            destinationLogger.info("Destination transition kind=airplay result=connected")
        } else if selectedDestination.kind == .airPlay {
            availableDestinations.removeAll { $0.kind == .airPlay }
            player?.pauseForDestinationLoss()
            connectionState = .disconnected
            needsLocalContinuation = true
            destinationLogger.info("Destination disconnected kind=airplay result=paused")
        }
    }

    func logicalPlaybackEnded() {
        needsLocalContinuation = false
        if selectedDestination.kind == .device {
            selectRendererHost(.device)
        }
    }

    private func requestDevicePlayback(autoplay: Bool) {
        selectedDestination = .device
        connectionState = .connected
        needsLocalContinuation = false
        selectRendererHost(.device)
        player?.completeRendererHandoff(autoplay: autoplay)
        destinationLogger.info("Destination transition kind=device result=connected")
    }

    private func selectRendererHost(_ host: PlayerRendererHost?) {
        guard hostArbiter.select(host) else { return }
        // Changing the host invalidates the old SwiftUI renderer before the new
        // host is allowed to attach its AV surface or VLC drawable.
        rendererHost = hostArbiter.selectedHost
        player?.rendererHostDidChange()
    }

    private func rebuildAvailableDestinations() {
        let airPlay = availableDestinations.filter { $0.kind == .airPlay }
        availableDestinations = [.device] + sceneDestinations.values.sorted { $0.name < $1.name } + airPlay
    }
}
