//
//  SettingsScreen.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import OSLog
import SwiftUI

private enum LibraryLanguageSource: String, CaseIterable, Identifiable {
    case automatic
    case prefix
    case suffix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            "Automatic"
        case .prefix:
            "Prefix"
        case .suffix:
            "Suffix"
        }
    }
}

private enum PlaybackPreference: String, CaseIterable, Identifiable {
    case automatic
    case avPlayer
    case vlc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            "Automatic"
        case .avPlayer:
            "AVPlayer"
        case .vlc:
            "VLC"
        }
    }
}

struct SettingsScreen: View {
    private struct PrefixOption: Identifiable, Equatable {
        let prefix: String
        let matches: Int
        let categoryNames: [String]

        var id: String { prefix }

        var sampleLabel: String {
            categoryNames.prefix(2).joined(separator: ", ")
        }
    }

    @Environment(Catalog.self) private var catalog
    @Environment(ProviderStore.self) private var providerStore

    @State private var baseURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var excludedPrefixesInput = ""
    @State private var availablePrefixOptions: [PrefixOption] = []
    @State private var selectedVisiblePrefixes: Set<String> = []
    @State private var isShowingPrefixSelector = false
    @State private var isLoadingPrefixOptions = false
    @State private var prefixDiscoveryError: String?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var catalogueSummary: ProviderCatalogueSummary?
    @State private var isLoadingCatalogueSummary = false

    var body: some View {
        #if os(macOS)
        macSettingsBody
            .frame(minWidth: 680, idealWidth: 720, minHeight: 480, idealHeight: 540)
            .onAppear(perform: loadCurrentValues)
            .task(id: providerStore.revision) {
                await observeCatalogueSummary()
            }
            .sheet(isPresented: $isShowingPrefixSelector) {
                prefixSelectionSheet
            }
        #else
        Form {
            generalOverviewSection
            providerCredentialsSection
            providerActionsSection
            librarySection
            playbackSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .withBackgroundActivityToolbar()
        .onAppear(perform: loadCurrentValues)
        .task(id: providerStore.revision) {
            await observeCatalogueSummary()
        }
        .sheet(isPresented: $isShowingPrefixSelector) {
            NavigationStack {
                prefixSelectionSheet
            }
            .presentationDetents([.medium, .large])
        }
        #endif
    }

    #if os(macOS)
    private var macSettingsBody: some View {
        TabView {
            settingsPane {
                Form {
                    generalOverviewSection
                    aboutSection
                }
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            settingsPane {
                Form {
                    providerCredentialsSection
                    providerActionsSection
                }
            }
            .tabItem {
                Label("Provider", systemImage: "key.horizontal")
            }

            settingsPane {
                Form {
                    librarySection
                }
            }
            .tabItem {
                Label("Library", systemImage: "square.grid.2x2")
            }

            settingsPane {
                Form {
                    playbackSection
                }
            }
            .tabItem {
                Label("Playback", systemImage: "play.rectangle")
            }
        }
    }

    private func settingsPane<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .formStyle(.grouped)
            .padding(20)
    }
    #endif

    private var generalOverviewSection: some View {
        Section {
            catalogueStatsGrid

            LabeledContent("Provider") {
                providerStatusBadge
            }

            LabeledContent("Endpoint") {
                Text(providerEndpointSummary)
                    .foregroundStyle(providerStore.hasConfiguration ? .primary : .secondary)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Credentials") {
                Text(providerStore.hasConfiguration ? "Stored Securely" : "Not Configured")
                    .foregroundStyle(providerStore.hasConfiguration ? .primary : .secondary)
            }

            LabeledContent("Excluded Prefixes") {
                Text(excludedPrefixesSummary)
                    .foregroundStyle(providerStore.hasConfiguration ? .primary : .secondary)
                    .multilineTextAlignment(.trailing)
            }

            if let validationError = providerStore.lastValidationError, !providerStore.hasConfiguration {
                LabeledContent("Last Error") {
                    Text(validationError)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let statusMessage {
                LabeledContent(statusIsError ? "Save Error" : "Recent Change") {
                    Text(statusMessage)
                        .foregroundStyle(statusIsError ? .red : .green)
                        .multilineTextAlignment(.trailing)
                }
            }
        } footer: {
            Text("Provider credentials unlock catalog loading, search, recommendations, and playback.")
        }
    }

    @ViewBuilder
    private var catalogueStatsGrid: some View {
        #if os(macOS)
        HStack(spacing: 12) {
            statsCard(
                title: "Movies",
                value: movieCountText,
                subtitle: movieCountSubtitle
            )
            statsCard(
                title: "Series",
                value: seriesCountText,
                subtitle: seriesCountSubtitle
            )
        }
        #else
        VStack(spacing: 12) {
            statsCard(
                title: "Movies",
                value: movieCountText,
                subtitle: movieCountSubtitle
            )
            statsCard(
                title: "Series",
                value: seriesCountText,
                subtitle: seriesCountSubtitle
            )
        }
        #endif
    }

    private func statsCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.weight(.bold))

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var movieCountText: String {
        if isLoadingCatalogueSummary && catalogueSummary == nil {
            return "..."
        }
        return (catalogueSummary?.movieCount ?? 0).formatted()
    }

    private var seriesCountText: String {
        if isLoadingCatalogueSummary && catalogueSummary == nil {
            return "..."
        }
        return (catalogueSummary?.seriesCount ?? 0).formatted()
    }

    private var movieCountSubtitle: String {
        guard let catalogueSummary else {
            return providerStore.hasConfiguration ? "Counting titles while your provider is being indexed." : "Configure a provider to show catalogue size."
        }

        if catalogueSummary.totalMovieCategories == 0 {
            return "No movie categories found yet."
        }

        if catalogueSummary.indexedMovieCategories < catalogueSummary.totalMovieCategories {
            return "\(catalogueSummary.indexedMovieCategories) of \(catalogueSummary.totalMovieCategories) movie categories indexed so far"
        }

        return "Included in your provider"
    }

    private var seriesCountSubtitle: String {
        guard let catalogueSummary else {
            return providerStore.hasConfiguration ? "Counting titles while your provider is being indexed." : "Configure a provider to show catalogue size."
        }

        if catalogueSummary.totalSeriesCategories == 0 {
            return "No series categories found yet."
        }

        if catalogueSummary.indexedSeriesCategories < catalogueSummary.totalSeriesCategories {
            return "\(catalogueSummary.indexedSeriesCategories) of \(catalogueSummary.totalSeriesCategories) series categories indexed so far"
        }

        return "Included in your provider"
    }

    private var providerCredentialsSection: some View {
        Section {
            TextField(text: $baseURL, prompt: Text("example.com or https://example.com")) {
                Text("Base URL")
            }
            .providerInputStyle()
            #if os(iOS)
            .keyboardType(.URL)
            .textContentType(.URL)
            #endif

            TextField(text: $username, prompt: Text("Required")) {
                Text("Username")
            }
            .providerInputStyle()
            #if os(iOS)
            .textContentType(.username)
            #endif

            SecureField(text: $password, prompt: Text("Required")) {
                Text("Password")
            }
            #if os(iOS)
            .textContentType(.password)
            #endif
        } header: {
            Text("Provider Credentials")
        } footer: {
            Text("The password is stored in the system keychain. The API URL is normalized to the provider's `player_api.php` endpoint when needed.")
        }
    }

    private var providerActionsSection: some View {
        Section("Provider Actions") {
            Button(providerStore.hasConfiguration ? "Update Provider" : "Save Provider") {
                save()
            }
            .buttonStyle(.borderedProminent)

            Button("Clear Provider", role: .destructive) {
                clear()
            }
            .disabled(!providerStore.hasConfiguration && baseURL.isEmpty && username.isEmpty && password.isEmpty)
        }
    }

    private var librarySection: some View {
        Section {
            LabeledContent("Excluded Prefixes") {
                Text(excludedPrefixesSummary)
                    .foregroundStyle(providerStore.hasConfiguration ? .primary : .secondary)
                    .multilineTextAlignment(.trailing)
            }

            Button("Choose Visible Prefixes") {
                openPrefixSelector()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!providerStore.hasConfiguration)

            Toggle("Group categories by language", isOn: .constant(false))
                .disabled(true)

            TextField(text: .constant(""), prompt: Text("Not configured")) {
                Text("Category Prefix")
            }
            .disabled(true)
            .providerInputStyle()

            Picker("Language Source", selection: .constant(LibraryLanguageSource.automatic)) {
                ForEach(LibraryLanguageSource.allCases) { source in
                    Text(source.title)
                        .tag(source)
                }
            }
            .disabled(true)
        } header: {
            Text("Library Organization")
        } footer: {
            Text("All detected prefixes start visible. Deselect a prefix to hide matching categories across browse, search indexing, and recommendations.")
        }
    }

    @ViewBuilder
    private var prefixSelectionSheet: some View {
        #if os(macOS)
        prefixSelectionContent
            .frame(minWidth: 520, idealWidth: 580, minHeight: 420, idealHeight: 520)
        #else
        prefixSelectionContent
        #endif
    }

    private var prefixSelectionContent: some View {
        VStack(spacing: 0) {
            if let prefixDiscoveryError {
                Text(prefixDiscoveryError)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            if isLoadingPrefixOptions {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading prefixes from the current provider...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if availablePrefixOptions.isEmpty {
                ContentUnavailableView(
                    "No Prefixes Found",
                    systemImage: "text.badge.xmark",
                    description: Text("No category prefixes were detected for the current provider.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(availablePrefixOptions) { option in
                    prefixSelectorRow(for: option)
                }
            }
        }
        .navigationTitle("Visible Prefixes")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismissPrefixSelector()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveVisiblePrefixSelection()
                }
                .disabled(!providerStore.hasConfiguration || isLoadingPrefixOptions)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadAvailablePrefixes(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!providerStore.hasConfiguration || isLoadingPrefixOptions)
            }
        }
        .task(id: isShowingPrefixSelector) {
            guard isShowingPrefixSelector, availablePrefixOptions.isEmpty, providerStore.hasConfiguration else { return }
            await loadAvailablePrefixes(force: false)
        }
    }

    private func prefixSelectorRow(for option: PrefixOption) -> some View {
        Button {
            toggleVisiblePrefix(option.prefix)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedVisiblePrefixes.contains(option.prefix) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedVisiblePrefixes.contains(option.prefix) ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(option.prefix)
                            .font(.headline.monospaced())
                        Spacer()
                        Text(selectedVisiblePrefixes.contains(option.prefix) ? "Visible" : "Hidden")
                            .foregroundStyle(.secondary)
                    }

                    if !option.sampleLabel.isEmpty {
                        Text(option.sampleLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text("\(option.matches) categor\(option.matches == 1 ? "y" : "ies")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var playbackSection: some View {
        Section {
            Picker("Preferred Player", selection: .constant(PlaybackPreference.automatic)) {
                ForEach(PlaybackPreference.allCases) { preference in
                    Text(preference.title)
                        .tag(preference)
                }
            }
            .disabled(true)

            Toggle("Enable subtitles by default", isOn: .constant(false))
                .disabled(true)

            TextField(text: .constant(""), prompt: Text("Not configured")) {
                Text("Preferred Audio Language")
            }
            .disabled(true)
            .providerInputStyle()
        } header: {
            Text("Playback Defaults")
        } footer: {
            Text("Dedicated playback defaults are not exposed here yet. Today those preferences are learned from the active player session.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersionDescription)
            LabeledContent("Platform", value: platformDescription)
            LabeledContent("Configuration Revision", value: String(providerStore.revision))
            LabeledContent("Secure Storage", value: "System Keychain")
        }
    }

    private var providerStatusBadge: some View {
        Label {
            Text(providerStore.hasConfiguration ? "Configured" : "Needs Setup")
        } icon: {
            Image(systemName: providerStore.hasConfiguration ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(providerStore.hasConfiguration ? .green : .orange)
    }

    private var providerEndpointSummary: String {
        let trimmed = providerStore.baseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not configured" : trimmed
    }

    private var excludedPrefixesSummary: String {
        let trimmed = providerStore.excludedCategoryPrefixesInput().trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "None" : trimmed
    }

    private var appVersionDescription: String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, build) {
        case let (version?, build?) where version != build:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        case let (_, build?):
            return build
        default:
            return "Unknown"
        }
    }

    private var platformDescription: String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "Apple Platform"
        #endif
    }

    private func loadCurrentValues() {
        baseURL = providerStore.baseURLInput
        username = providerStore.username()
        password = providerStore.password()
        excludedPrefixesInput = providerStore.excludedCategoryPrefixesInput()
        selectedVisiblePrefixes = Set()
    }

    private func observeCatalogueSummary() async {
        guard providerStore.hasConfiguration else {
            await MainActor.run {
                catalogueSummary = nil
                isLoadingCatalogueSummary = false
            }
            return
        }

        await MainActor.run {
            isLoadingCatalogueSummary = true
        }

        while !Task.isCancelled && providerStore.hasConfiguration {
            do {
                let summary = try await catalog.providerCatalogueSummary()
                await MainActor.run {
                    catalogueSummary = summary
                    isLoadingCatalogueSummary = false
                }
            } catch {
                await MainActor.run {
                    isLoadingCatalogueSummary = false
                }
            }

            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func save() {
        do {
            try providerStore.save(baseURL: baseURL, username: username, password: password)
            loadCurrentValues()
            statusMessage = "Provider configuration saved."
            statusIsError = false
            logger.info("Provider configuration saved.")
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
            logger.error("Failed to save provider configuration: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clear() {
        do {
            try providerStore.clear()
            loadCurrentValues()
            statusMessage = "Provider configuration cleared."
            statusIsError = false
            logger.info("Provider configuration cleared.")
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
            logger.error("Failed to clear provider configuration: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveExcludedPrefixes() {
        do {
            try providerStore.saveExcludedCategoryPrefixes(excludedPrefixesInput)
            loadCurrentValues()
            statusMessage = "Excluded prefixes saved for the current provider."
            statusIsError = false
            logger.info("Excluded category prefixes saved.")
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
            logger.error("Failed to save excluded category prefixes: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func openPrefixSelector() {
        synchronizeVisiblePrefixes()
        prefixDiscoveryError = nil
        isShowingPrefixSelector = true
    }

    private func dismissPrefixSelector() {
        isShowingPrefixSelector = false
    }

    private func toggleVisiblePrefix(_ prefix: String) {
        if selectedVisiblePrefixes.contains(prefix) {
            selectedVisiblePrefixes.remove(prefix)
        } else {
            selectedVisiblePrefixes.insert(prefix)
        }
    }

    private func saveVisiblePrefixSelection() {
        let excludedPrefixes = availablePrefixOptions
            .map(\.prefix)
            .filter { !selectedVisiblePrefixes.contains($0) }

        excludedPrefixesInput = excludedPrefixes
            .joined(separator: ", ")
        saveExcludedPrefixes()
        dismissPrefixSelector()
    }

    private func loadAvailablePrefixes(force: Bool) async {
        guard providerStore.hasConfiguration else { return }
        if isLoadingPrefixOptions && !force { return }

        await MainActor.run {
            isLoadingPrefixOptions = true
            prefixDiscoveryError = nil
        }

        do {
            let config = try providerStore.requiredConfiguration()
            let service = XtreamService(
                .shared,
                baseURL: config.apiURL,
                username: config.username,
                password: config.password
            )

            async let vodCategories = service.getCategories(of: .vod)
            async let seriesCategories = service.getCategories(of: .series)
            let categories = try await vodCategories + seriesCategories

            let prefixes = Self.detectedPrefixOptions(from: categories)
            await MainActor.run {
                availablePrefixOptions = prefixes
                synchronizeVisiblePrefixes()
                isLoadingPrefixOptions = false
            }
        } catch {
            await MainActor.run {
                isLoadingPrefixOptions = false
                prefixDiscoveryError = error.localizedDescription
            }
        }
    }

    private static func detectedPrefixOptions(from categories: [XtreamCategory]) -> [PrefixOption] {
        var counts: [String: Int] = [:]
        var samples: [String: [String]] = [:]

        for category in categories {
            let tagged = LanguageTaggedText(category.name)
            guard let prefix = tagged.prefixLanguageCode else { continue }

            counts[prefix, default: 0] += 1
            let sample = tagged.groupedDisplayName
            if !sample.isEmpty, !(samples[prefix] ?? []).contains(sample) {
                samples[prefix, default: []].append(sample)
            }
        }

        return counts.keys.sorted().map { prefix in
            PrefixOption(
                prefix: prefix,
                matches: counts[prefix, default: 0],
                categoryNames: Array(samples[prefix, default: []].prefix(3))
            )
        }
    }

    private func synchronizeVisiblePrefixes() {
        let excludedPrefixes = Set(providerStore.excludedCategoryPrefixes())
        let availablePrefixes = Set(availablePrefixOptions.map(\.prefix))

        if availablePrefixes.isEmpty {
            selectedVisiblePrefixes = []
            return
        }

        selectedVisiblePrefixes = availablePrefixes.subtracting(excludedPrefixes)
    }
}

private extension View {
    @ViewBuilder
    func providerInputStyle() -> some View {
        #if os(macOS)
        self
        #else
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #endif
    }
}

#Preview {
    SettingsScreen()
        .environment(ProviderStore())
}
