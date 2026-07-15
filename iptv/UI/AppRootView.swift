import SwiftUI

@MainActor
@Observable
final class RecoverableBootstrap<Value> {
    @ObservationIgnored
    private let load: () throws -> Value

    private(set) var value: Value?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private var didAttempt = false

    init(load: @escaping () throws -> Value) {
        self.load = load
    }

    func startIfNeeded() {
        guard !didAttempt else { return }
        attemptLoad()
    }

    func retry() {
        attemptLoad()
    }

    private func attemptLoad() {
        guard !isLoading else { return }

        didAttempt = true
        isLoading = true
        errorMessage = nil

        do {
            value = try load()
        } catch {
            value = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct AppRootView: View {
    @Environment(ProviderManager.self) private var providerManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var connectionMonitor = InternetConnectionMonitor.shared

    var body: some View {
        Group {
            if providerManager.requiresOnboarding {
                OnboardingFlowView()
            } else {
                ContentView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !connectionMonitor.isConnected {
                Label("Offline — showing saved content", systemImage: "wifi.slash")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.92))
                    .foregroundStyle(.black)
                    .accessibilityIdentifier("connectivity.offline")
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active,
                  connectionMonitor.isConnected,
                  !providerManager.requiresOnboarding
            else { return }
            await providerManager.refreshActiveProviderIfStale()
        }
        .task(id: connectionMonitor.isConnected) {
            guard connectionMonitor.isConnected,
                  scenePhase == .active,
                  !providerManager.requiresOnboarding
            else { return }
            await providerManager.refreshActiveProviderIfStale()
        }
    }
}

struct BootstrapFailureView: View {
    let message: String
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t Open iptv", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
                .disabled(isRetrying)
                .accessibilityIdentifier("bootstrap.retry")
        }
        .padding()
    }
}
