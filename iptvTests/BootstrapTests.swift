import Foundation
import Testing

@testable import iptv

@MainActor
struct BootstrapTests {
    private enum TestError: Error {
        case unavailable
    }

    @Test func bootstrapFailureCanBeRetriedWithoutDuplicatingInitialAttempts() {
        var attempts = 0
        let bootstrap = RecoverableBootstrap<Int> {
            attempts += 1
            if attempts == 1 {
                throw TestError.unavailable
            }
            return 42
        }

        bootstrap.startIfNeeded()

        #expect(attempts == 1)
        #expect(bootstrap.value == nil)
        #expect(bootstrap.errorMessage != nil)
        #expect(bootstrap.isLoading == false)

        bootstrap.startIfNeeded()
        #expect(attempts == 1)

        bootstrap.retry()

        #expect(attempts == 2)
        #expect(bootstrap.value == 42)
        #expect(bootstrap.errorMessage == nil)
        #expect(bootstrap.isLoading == false)
    }

    @Test(arguments: [
        (true, true, false, true),
        (false, true, false, false),
        (true, false, false, false),
        (true, true, true, false),
        (false, false, true, false),
    ])
    func providerRefreshEligibility(
        isSceneActive: Bool,
        isConnected: Bool,
        requiresOnboarding: Bool,
        expected: Bool
    ) {
        let eligibility = ProviderRefreshEligibility(
            isSceneActive: isSceneActive,
            isConnected: isConnected,
            requiresOnboarding: requiresOnboarding
        )

        #expect(eligibility.shouldRefresh == expected)
    }
}
