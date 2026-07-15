import SwiftUI

struct OnboardingFlowView: View {
    private enum Route: Hashable {
        case credentials
        case syncing
        case failed
    }

    @Environment(ProviderManager.self) private var providerManager

    @State private var selectedKind: ProviderSourceKind = .xtream
    @State private var providerFields = ProviderFields(name: "", endpoint: "", username: "", password: "")
    @State private var path: [Route] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showsValidationErrors = false
    @State private var syncingRevision: Int?

    var body: some View {
        NavigationStack(path: $path) {
            onboardingScreen {
                sourceStep
            }
            .navigationTitle("Welcome to iptv")
            .navigationDestination(for: Route.self) { route in
                switch route {
                    case .credentials:
                        onboardingScreen {
                            credentialsStep
                        }
                        .navigationTitle(selectedKind.title)
                        .navigationBarBackButtonHidden(isSubmitting)
                    case .syncing:
                        onboardingScreen {
                            syncingStep
                        }
                        .navigationTitle("Syncing")
                        .navigationBarBackButtonHidden(true)
                    case .failed:
                        onboardingScreen {
                            failedStep
                        }
                        .navigationTitle("Sync failed")
                }
            }
        }
        .task(id: providerManager.revision) {
            await reactToProviderRevision()
        }
    }

    private func onboardingScreen<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content()
                .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
                .padding(32)
        }
    }

    private var sourceStep: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add a source to sync your movies, series, and live TV catalog.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .trailing, spacing: 12) {
                ForEach(ProviderSourceKind.allCases) { kind in
                    Button {
                        selectedKind = kind
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: selectedKind == kind ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedKind == kind ? .green : .secondary)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(kind.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(kind.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selectedKind == kind ? Color.green : Color.secondary.opacity(0.18), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.source.\(kind.rawValue)")
                }
                
                HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("M3U8 Playlist")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Playlist source support is planned for a future update.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        Text("soon")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.12), in: Capsule())
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }
                .accessibilityIdentifier("onboarding.source.m3u8")
            }

            NavigationLink(value: Route.credentials) {
                Text("Continue")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.source.continue")
        }
        }
    }

    private var credentialsStep: some View {
        providerForm(
            copy: "Your Xtream credentials are used to sync the catalog locally. Playback and browsing use the local library after sync completes.",
            saveLabel: "Start Sync",
            isRetry: false
        )
    }

    private var failedStep: some View {
        providerForm(
            copy: providerManager.session?.syncErrorMessage ?? errorMessage ?? fallbackSyncErrorMessage,
            saveLabel: "Retry Sync",
            isRetry: true
        )
    }

    private func providerForm(
        copy: String,
        saveLabel: String,
        isRetry: Bool
    ) -> some View {
        Form {
            Section {
                Text(copy)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(isRetry ? "onboarding.error.message" : "onboarding.credentials.copy")
            }

            ProviderEditorSection(
                fields: providerFields,
                sourceKind: selectedKind,
                isConfigured: false,
                isSaving: isSubmitting,
                saveLabel: saveLabel,
                errorMessage: errorMessage,
                showsValidationErrors: showsValidationErrors,
                saveAccessibilityIdentifier: isRetry ? "onboarding.retry" : "onboarding.provider.save",
                onSave: {
                    Task { await submit() }
                },
                onRemove: nil
            )

        }
        .formStyle(.grouped)
#if os(macOS)
        .scrollContentBackground(.hidden)
#endif
    }

    private var syncingStep: some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)

            Text(phaseMessage)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                syncRow(title: "Movies", status: providerManager.session?.movieSyncStatus ?? .idle)
                syncRow(title: "Series", status: providerManager.session?.seriesSyncStatus ?? .idle)
                syncRow(title: "Live", status: providerManager.session?.liveSyncStatus ?? .idle)
            }
        }
        .padding(28)
        .frame(maxWidth: 440)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("onboarding.sync.progress")
    }

    private func syncRow(title: String, status: SyncManager.SyncStatus) -> some View {
        HStack(spacing: 12) {
            syncStatusIcon(for: status)
                .frame(width: 24, height: 24)
            Text(title)
                .font(.headline)
            Spacer()
        }
        .foregroundStyle(status == .failure ? .red : .primary)
    }

    @ViewBuilder
    private func syncStatusIcon(for status: SyncManager.SyncStatus) -> some View {
        switch status {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .active:
                ProgressView()
            case .failure:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            case .idle:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
        }
    }

    private var phaseMessage: String {
        switch providerManager.session?.initialSyncPhase ?? .idle {
            case .idle:
                "Preparing your library…"
            case .checkingProvider:
                "Contacting your provider…"
            case .replacingCatalog:
                "Replacing the local catalog…"
            case .syncingMovies:
                "Syncing movie categories…"
            case .syncingSeries:
                "Syncing series categories…"
            case .syncingLive:
                "Syncing live categories…"
            case .validatingCatalog:
                "Checking received catalog data…"
            case .succeeded:
                "Catalog synced."
            case .failed:
                "Sync failed."
        }
    }

    private var fallbackSyncErrorMessage: String {
        "We couldn’t sync this source. Check the URL, username, and password, then try again."
    }

    private func reactToProviderRevision() async {
        do {
            guard let configuration = try providerManager.activeProviderConfiguration() else {
                providerFields = ProviderFields(name: "", endpoint: "", username: "", password: "")
                selectedKind = .xtream
                showsValidationErrors = false
                errorMessage = nil
                path = []
                return
            }

            providerFields = ProviderFields(
                name: configuration.name,
                endpoint: configuration.endpoint.absoluteString,
                username: configuration.username,
                password: configuration.password,
                allowsInsecureHTTP: configuration.allowsInsecureHTTP
            )
            selectedKind = configuration.kind
            showsValidationErrors = false

            guard providerManager.session != nil else {
                switch providerManager.accessState {
                    case .credentialsRequired:
                        errorMessage = "Enter the provider password to continue."
                    case .credentialsUnavailable:
                        errorMessage = "The saved password couldn’t be read. Enter it again to continue."
                    case .insecureTransportApprovalRequired:
                        errorMessage = "Review the HTTP warning and explicitly allow insecure HTTP to continue."
                    case .noProvider, .ready:
                        errorMessage = "Review the provider settings and try again."
                }
                path = [.credentials]
                return
            }

            guard !providerManager.activeProviderIsInitialized else { return }
            path = [.credentials, .syncing]
            await syncActiveProvider(for: providerManager.revision)
        } catch {
            errorMessage = error.localizedDescription
            path = [.credentials]
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        showsValidationErrors = true
        guard let configuration = providerFields.build(
            id: providerManager.activeProviderID,
            kind: selectedKind
        ) else {
            errorMessage = "Correct the highlighted provider fields."
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            if providerManager.activeProviderID == nil {
                try providerManager.initialize(configuration)
            } else {
                try providerManager.update(provider: configuration)
            }

            showsValidationErrors = false
            path = [.credentials, .syncing]
            isSubmitting = false
            await syncActiveProvider(for: providerManager.revision)
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
        }
    }

    private func syncActiveProvider(for revision: Int) async {
        guard syncingRevision != revision else { return }
        syncingRevision = revision
        defer { syncingRevision = nil }

        let result = await providerManager.runInitialSyncForActiveProvider()
        if result == .failure {
            errorMessage = providerManager.session?.syncErrorMessage ?? fallbackSyncErrorMessage
            path = [.credentials, .failed]
        }
    }
}
