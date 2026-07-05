import SwiftUI

struct AppRootView: View {
    @Environment(ProviderManager.self) private var providerManager

    var body: some View {
        if providerManager.requiresOnboarding {
            OnboardingFlowView()
        } else {
            ContentView()
        }
    }
}

