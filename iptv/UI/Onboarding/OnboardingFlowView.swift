import SwiftUI

struct OnboardingFlowView: View {
    private enum OnboardingStep: Equatable {
        case source
        case credentials
        case syncing
        case failed
    }

    @Environment(ProviderManager.self) private var providerManager

    @State private var selectedKind: ProviderSourceKind = .xtream
    @State private var providerFields = ProviderFields(name: "", endpoint: "", username: "", password: "")
    @State private var step: OnboardingStep = .source
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didStartExistingProviderSync = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                if step != .source {
                    Button {
                        step = .source
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("onboarding.back")
                }

                content
            }
            .frame(maxWidth: 720)
            .padding(32)
        }
        .task {
            await startExistingProviderSyncIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
            case .source:
                sourceStep
            case .credentials:
                credentialsStep
            case .syncing:
                syncingStep
            case .failed:
                failedStep
        }
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Welcome to iptv")
                    .font(.largeTitle.weight(.bold))
                Text("Add a source to sync your movies, series, and live TV catalog.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
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
                
                Button {} label: {
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

                        Text("Coming soon")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(true)
                .accessibilityIdentifier("onboarding.source.m3u8")
            }

            Button("Continue") {
                step = .credentials
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.source.continue")
        }
    }

    private var credentialsStep: some View {
        providerForm(
            title: selectedKind.title,
            copy: "Your Xtream credentials are used to sync the catalog locally. Playback and browsing use the local library after sync completes.",
            saveLabel: "Start Sync",
            showsBackButton: false
        )
    }

    private var failedStep: some View {
        providerForm(
            title: "Sync failed",
            copy: providerManager.session?.syncErrorMessage ?? errorMessage ?? fallbackSyncErrorMessage,
            saveLabel: "Retry Sync",
            showsBackButton: true
        )
    }

    private func providerForm(
        title: String,
        copy: String,
        saveLabel: String,
        showsBackButton: Bool
    ) -> some View {
        Form {
            Section {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(copy)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(showsBackButton ? "onboarding.error.message" : "onboarding.credentials.copy")
            }

            ProviderEditorSection(
                fields: providerFields,
                sourceKind: selectedKind,
                isConfigured: false,
                isSaving: isSubmitting,
                saveLabel: saveLabel,
                errorMessage: errorMessage,
                saveAccessibilityIdentifier: showsBackButton ? "onboarding.retry" : "onboarding.provider.save",
                onSave: {
                    Task { await submit() }
                },
                onClear: nil
            )

            if showsBackButton {
                Section {
                    Button("Back to source") {
                        step = .source
                    }
                    .buttonStyle(.bordered)
                }
            }
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
            case .clearingLibrary:
                "Preparing local storage…"
            case .syncingMovies:
                "Syncing movie categories…"
            case .syncingSeries:
                "Syncing series categories…"
            case .syncingLive:
                "Syncing live categories…"
            case .succeeded:
                "Catalog synced."
            case .failed:
                "Sync failed."
        }
    }

    private var fallbackSyncErrorMessage: String {
        "We couldn’t sync this source. Check the URL, username, and password, then try again."
    }

    private func startExistingProviderSyncIfNeeded() async {
        guard !didStartExistingProviderSync else { return }
        guard let session = providerManager.session, !providerManager.activeProviderIsInitialized else {
            step = .source
            return
        }

        didStartExistingProviderSync = true
        providerFields.name = session.provider.name
        providerFields.endpoint = session.provider.endpoint.absoluteString
        providerFields.username = session.provider.username
        providerFields.password = session.provider.password
        selectedKind = session.provider.kind
        step = .syncing

        let result = await providerManager.runInitialSyncForActiveProvider()
        if result == .failure {
            errorMessage = session.syncErrorMessage ?? fallbackSyncErrorMessage
            step = .failed
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        guard let draft = providerFields.build(id: providerManager.session?.providerID, kind: selectedKind) else {
            errorMessage = "Please complete all provider fields."
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            if providerManager.session == nil {
                try providerManager.initialize(draft)
            } else {
                try providerManager.update(provider: draft)
            }

            step = .syncing
            let result = await providerManager.runInitialSyncForActiveProvider()
            isSubmitting = false

            if result == .failure {
                errorMessage = providerManager.session?.syncErrorMessage ?? fallbackSyncErrorMessage
                step = .failed
            }
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
        }
    }
}

