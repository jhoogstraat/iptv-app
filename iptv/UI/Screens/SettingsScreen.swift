//
//  SettingsScreen.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import OSLog
import SwiftUI
import SQLiteData
import Dependencies

private enum PlaybackPreference: String, CaseIterable, Identifiable {
    case automatic
    case avPlayer = "av"
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

private enum SupportDocument: String, Identifiable {
    case help
    case licenses
    case terms

    var id: Self { self }

    var title: String {
        switch self {
        case .help: "Help"
        case .licenses: "Open-Source Licenses"
        case .terms: "Terms and Privacy"
        }
    }

    var body: String {
        switch self {
        case .help:
            "Add an Xtream-compatible provider in Settings, sync the catalog, then browse or search local content. Downloads are available for direct movies and episodes. If playback fails, verify credentials, transport approval, and provider availability, then retry."
        case .licenses:
            "This app uses open-source components including VLCKit, GRDB, SQLiteData, Nuke, Swift Collections, and Point-Free Swift libraries. Their license notices are distributed with the corresponding source packages and binary artifacts."
        case .terms:
            "This client does not provide media or subscriptions. You are responsible for the provider credentials and content you configure and for complying with applicable rights and laws. Provider credentials are stored in the system keychain; catalog and viewing state are stored locally on this device."
        }
    }
}

private enum SettingsDestination: String, CaseIterable, Identifiable, Hashable {
    case provider
    case profiles
    case library
    case playback
    case about

    var id: Self { self }

    var title: String {
        switch self {
            case .provider: "Provider"
            case .profiles: "Profiles"
            case .library: "Library"
            case .playback: "Playback"
            case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
            case .provider: "Connection, credentials, and sync status"
            case .profiles: "Separate favorites and watch progress"
            case .library: "Category visibility and organization"
            case .playback: "Player defaults and media behavior"
            case .about: "Version, help, and legal information"
        }
    }

    var systemImage: String {
        switch self {
            case .provider: "key.horizontal"
            case .profiles: "person.2"
            case .library: "square.grid.2x2"
            case .playback: "play.rectangle"
            case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
            case .provider: .blue
            case .profiles: .green
            case .library: .purple
            case .playback: .red
            case .about: .gray
        }
    }
}

struct MediaCount: FetchKeyRequest {
    struct Value {
        var movies = 0
        var series = 0
        var live = 0
        var movieCategories = 0
        var seriesCategories = 0
        var liveCategories = 0
    }

    let provider: Provider.ID?

    func fetch(_ db: Database) throws -> Value {
        try Value(
            movies: Media.where { $0.type.eq(MediaType.movie) }.fetchCount(db),
            series: Media.where { $0.type.eq(MediaType.series) }.fetchCount(db),
            live: Media.where { $0.type.eq(MediaType.live) }.fetchCount(db),
            movieCategories: Category.where { $0.type.eq(MediaType.movie) }.fetchCount(db),
            seriesCategories: Category.where { $0.type.eq(MediaType.series) }.fetchCount(db),
            liveCategories: Category.where { $0.type.eq(MediaType.live) }.fetchCount(db)
        )
    }
}

struct ProviderSettingsRevisionState {
    private(set) var loadedRevision: Int?

    mutating func didLoad(revision: Int) {
        loadedRevision = revision
    }

    mutating func clear() {
        loadedRevision = nil
    }

    func canSave(currentRevision: Int) -> Bool {
        loadedRevision == currentRevision
    }
}

struct ProviderRemovalConfirmationState {
    private(set) var pendingProviderID: Provider.ID?

    var isPresented: Bool {
        pendingProviderID != nil
    }

    mutating func requestRemoval(of providerID: Provider.ID) {
        pendingProviderID = providerID
    }

    mutating func cancel() {
        pendingProviderID = nil
    }

    mutating func confirm() -> Provider.ID? {
        defer { pendingProviderID = nil }
        return pendingProviderID
    }
}

struct SettingsScreen: View {
    
    @State private var providerFields: ProviderFields = .init(name: "", endpoint: "", username: "", password: "")
    @State private var providerErrorMessage: String?
    @State private var hiddenCategoryGroups: Set<String> = []
    @State private var isPrefixSelectorPresented = false
    @State private var removalConfirmation = ProviderRemovalConfirmationState()
    @State private var providerRevisionState = ProviderSettingsRevisionState()
    @State private var showsProviderValidationErrors = false
    @State private var isResyncing = false
    @State private var newProfileName = ""
    @State private var profileBeingRenamed: UserProfile?
    @State private var renamedProfileName = ""
    @State private var profileErrorMessage: String?
    @State private var supportDocument: SupportDocument?
    @AppStorage("preferredPlaybackBackend") private var playbackPreference: PlaybackPreference = .automatic
    @AppStorage("defaultSubtitleEnabled") private var subtitlesEnabledByDefault = false
    @AppStorage("preferredAudioLanguage") private var preferredAudioLanguage = ""
    @AppStorage("preferredSubtitleLanguage") private var preferredSubtitleLanguage = ""
    @AppStorage(UserProfileStore.activeProfileIDKey) private var activeProfileID = UserProfileStore.primaryProfileID
    @AppStorage(UserProfileStore.revisionKey) private var profileRevision = 0
    @AppStorage(CategoryPrefixVisibilityStore.revisionKey) private var prefixVisibilityRevision = 0
  
    @Dependency(\.defaultDatabase) var database
    
    @FetchOne(Provider.where(\.isActive)) var provider: Provider?
    @FetchAll(UserProfile.order { $0.createdAt.asc() }) private var profiles: [UserProfile]
    
    @Fetch(MediaCount(provider: nil)) var mediaCount = MediaCount.Value()
    @FetchAll(Category.where { $0.type.eq(MediaType.movie).or($0.type.eq(MediaType.series)) }) private var categories: [Category]
    
    @Environment(ProviderManager.self) private var providerManager
    
    @Environment(\.horizontalSizeClass) var sizeClass
   
    var body: some View {
        NavigationStack {
            settingsOverview
                .navigationDestination(for: SettingsDestination.self) { destination in
                    settingsDetail(for: destination)
                }
        }
        .task(id: providerManager.revision) { populateProviderFields() }
        .task(id: provider?.id) { loadPrefixVisibility() }
        .task(id: prefixVisibilityRevision) { loadPrefixVisibility() }
        .sheet(isPresented: $isPrefixSelectorPresented) {
            CategoryPrefixVisibilitySelector(
                groupKeys: detectedCategoryGroups,
                hiddenGroupKeys: hiddenCategoryGroups
            ) { nextHiddenGroups in
                hiddenCategoryGroups = nextHiddenGroups
                CategoryPrefixVisibilityStore.setHiddenGroupKeys(nextHiddenGroups, for: provider?.id)
                isPrefixSelectorPresented = false
            }
        }
        .confirmationDialog(
            "Remove Provider?",
            isPresented: Binding(
                get: { removalConfirmation.isPresented },
                set: { if !$0 { removalConfirmation.cancel() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Provider", role: .destructive) {
                confirmProviderRemoval()
            }
            Button("Cancel", role: .cancel) {
                removalConfirmation.cancel()
            }
        } message: {
            Text("This removes the provider, local catalog, favorites, and watch history. This action can’t be undone.")
        }
        .alert("Rename Profile", isPresented: Binding(
            get: { profileBeingRenamed != nil },
            set: { if !$0 { profileBeingRenamed = nil } }
        )) {
            TextField("Profile name", text: $renamedProfileName)
            Button("Rename", action: renameProfile)
            Button("Cancel", role: .cancel) { profileBeingRenamed = nil }
        }
        .sheet(item: $supportDocument) { document in
            NavigationStack {
                ScrollView {
                    Text(document.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(document.title)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { supportDocument = nil }
                    }
                }
            }
        }
    }
    
    private func populateProviderFields() {
        do {
            guard let configuration = try providerManager.activeProviderConfiguration() else {
                providerFields = .init(name: "", endpoint: "", username: "", password: "")
                providerRevisionState.clear()
                showsProviderValidationErrors = false
                providerErrorMessage = nil
                return
            }

            providerFields = .init(
                name: configuration.name,
                endpoint: configuration.endpoint.absoluteString,
                username: configuration.username,
                password: configuration.password,
                allowsInsecureHTTP: configuration.allowsInsecureHTTP
            )
            providerRevisionState.didLoad(revision: providerManager.revision)
            showsProviderValidationErrors = false
            providerErrorMessage = nil
        } catch {
            providerErrorMessage = error.localizedDescription
        }
    }
    
    @ViewBuilder
    private var settingsOverview: some View {
        Form {
            Section {
                ForEach(SettingsDestination.allCases) { destination in
                    NavigationLink(value: destination) {
                        SettingsDestinationRow(destination: destination)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
#if !os(macOS) && !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
#if os(macOS)
        .padding(20)
        .frame(minWidth: 600)
#endif
    }
    
    @ViewBuilder
    private func settingsDetail(for destination: SettingsDestination) -> some View {
        switch destination {
            case .provider:
                settingsDetailForm(title: "Provider") {
                    providerOverviewSection
                    providerConfigurationSection
                }
            case .profiles:
                settingsDetailForm(title: "Profiles") {
                    profilesSection
                }
            case .library:
                settingsDetailForm(title: "Library") {
                    librarySection
                }
            case .playback:
                settingsDetailForm(title: "Playback") {
                    playbackSection
                }
            case .about:
                settingsDetailForm(title: "About") {
                    supportSection
                }
        }
    }

    private var profilesSection: some View {
        Section {
            ForEach(profiles) { profile in
                Button {
                    UserProfileStore.setActive(profile.id)
                } label: {
                    HStack {
                        Label(profile.name, systemImage: "person.crop.circle")
                        Spacer()
                        if profile.id == activeProfileID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        deleteProfile(profile)
                    }
                    .disabled(profiles.count == 1)
                }
                .contextMenu {
                    Button("Rename") {
                        profileBeingRenamed = profile
                        renamedProfileName = profile.name
                    }
                    Button("Delete", role: .destructive) {
                        deleteProfile(profile)
                    }
                    .disabled(profiles.count == 1)
                }
            }

            HStack {
                TextField("New profile name", text: $newProfileName)
                    .onSubmit(createProfile)
                Button("Add", action: createProfile)
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let profileErrorMessage {
                Text(profileErrorMessage)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Viewer Profiles")
        } footer: {
            Text("Each profile has independent favorites and watch progress. Catalog and provider settings are shared.")
        }
    }

    private func createProfile() {
        do {
            _ = try UserProfileStore.create(name: newProfileName, database: database)
            newProfileName = ""
            profileErrorMessage = nil
        } catch {
            profileErrorMessage = error.localizedDescription
        }
    }

    private func deleteProfile(_ profile: UserProfile) {
        do {
            try UserProfileStore.delete(profile, database: database)
            profileErrorMessage = nil
        } catch {
            profileErrorMessage = error.localizedDescription
        }
    }

    private func renameProfile() {
        guard let profileBeingRenamed else { return }
        do {
            try UserProfileStore.rename(
                profileBeingRenamed,
                to: renamedProfileName,
                database: database
            )
            self.profileBeingRenamed = nil
            profileErrorMessage = nil
        } catch {
            profileErrorMessage = error.localizedDescription
        }
    }
    
    @ViewBuilder
    private func settingsDetailForm<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .navigationTitle(title)
#if !os(macOS) && !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
#if os(macOS)
        .padding(20)
        .frame(minWidth: 520)
#endif
    }
    


    @ViewBuilder
    private var providerOverviewSection: some View {
        let status = providerStatus
        Section {
            let layout = sizeClass == .compact
                        ? AnyLayout(VStackLayout(spacing: 20))
                        : AnyLayout(HStackLayout(spacing: 20))

            layout {
                StatsCard(title: "Movies", value: "\(mediaCount.movies)", subtitle: categoryCountDescription(mediaCount.movieCategories))
                StatsCard(title: "Series", value: "\(mediaCount.series)", subtitle: categoryCountDescription(mediaCount.seriesCategories))
                StatsCard(title: "Live", value: "\(mediaCount.live)", subtitle: categoryCountDescription(mediaCount.liveCategories))
            }
            
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Image(systemName: status.systemImage)
                    Text(status.title)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.color)
            }

            LabeledContent("Last Sync") {
                Text(providerManager.lastSuccessfulSync?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
                    .foregroundStyle(.secondary)
            }

            if status.title == "Sync Failed", let errorMessage = providerManager.session?.syncErrorMessage {
                LabeledContent("Sync Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
    
    private var providerStatus: (title: String, systemImage: String, color: Color) {
        guard let session = providerManager.session else {
            return ("Needs Setup", "exclamationmark.circle.fill", .orange)
        }

        switch session.sync {
            case .active:
                return ("Syncing", "arrow.trianglehead.2.clockwise.rotate.90", .blue)
            case .failure:
                return ("Sync Failed", "xmark.circle.fill", .red)
            case .idle, .success:
                if providerManager.activeProviderIsInitialized {
                    return ("Ready", "checkmark.circle.fill", .green)
                }
                return ("Needs Sync", "exclamationmark.circle.fill", .orange)
        }
    }

    private func categoryCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "category" : "categories")"
    }

    
    @ViewBuilder
    private var providerConfigurationSection: some View {
        ProviderEditorSection(
            fields: providerFields,
            sourceKind: provider?.kind ?? .xtream,
            isConfigured: providerManager.hasActiveProvider,
            isSaving: isResyncing,
            saveLabel: "Save",
            errorMessage: providerErrorMessage,
            showsValidationErrors: showsProviderValidationErrors,
            onSave: save,
            onRemove: clear
        )

        Section {
            Button {
                Task { await resync() }
            } label: {
                if isResyncing {
                    Label("Syncing Catalog", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                } else {
                    Label("Resync Catalog", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
            }
            .disabled(!providerManager.hasActiveProvider || isResyncing)
            .accessibilityIdentifier("settings.provider.resync")
        } header: {
            Text("Catalog")
        } footer: {
            Text("Resync replaces the local catalog from this provider. Favorites and watch history are preserved.")
        }
    }
    
    private var librarySection: some View {
        Section {
            LabeledContent("Excluded Prefixes") {
                Text(excludedPrefixesSummary)
                    .foregroundStyle(providerManager.hasActiveProvider ? .primary : .secondary)
                    .multilineTextAlignment(.trailing)
            }

            Button("Choose Visible Prefixes") {
                hiddenCategoryGroups = CategoryPrefixVisibilityStore.hiddenGroupKeys(for: provider?.id)
                isPrefixSelectorPresented = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!providerManager.hasActiveProvider || detectedCategoryGroups.isEmpty)

        } header: {
            Text("Library Organization")
        } footer: {
            Text("All detected prefixes start visible. Hidden prefixes are provider-scoped and excluded from browse and search.")
        }
    }

    private var detectedCategoryGroups: [String] {
        Set(categories.map { CategoryGrouping.key(for: $0.title) })
            .sorted {
                CategoryGrouping.title(for: $0).localizedStandardCompare(CategoryGrouping.title(for: $1)) == .orderedAscending
            }
    }

    private var excludedPrefixesSummary: String {
        guard providerManager.hasActiveProvider else { return "No active provider" }
        guard !detectedCategoryGroups.isEmpty else { return "None detected" }
        guard !hiddenCategoryGroups.isEmpty else { return "None" }

        let hiddenTitles = hiddenCategoryGroups
            .sorted { CategoryGrouping.title(for: $0) < CategoryGrouping.title(for: $1) }
            .map { CategoryGrouping.title(for: $0) }

        if hiddenTitles.count <= 3 {
            return hiddenTitles.joined(separator: ", ")
        }

        return "\(hiddenTitles.prefix(3).joined(separator: ", ")) + \(hiddenTitles.count - 3) more"
    }

    private func loadPrefixVisibility() {
        hiddenCategoryGroups = CategoryPrefixVisibilityStore.hiddenGroupKeys(for: provider?.id)
    }
    
    
    private var playbackSection: some View {
        Section {
            Picker("Preferred Player", selection: $playbackPreference) {
                ForEach(PlaybackPreference.allCases) { preference in
                    Text(preference.title)
                        .tag(preference)
                }
            }
            Toggle("Enable subtitles by default", isOn: $subtitlesEnabledByDefault)

            TextField(text: $preferredAudioLanguage, prompt: Text("For example: en")) {
                Text("Preferred Audio Language")
            }

            TextField(text: $preferredSubtitleLanguage, prompt: Text("For example: de")) {
                Text("Preferred Subtitle Language")
            }
        } header: {
            Text("Playback Defaults")
        } footer: {
            Text("Language values accept ISO codes such as en, de, or nl and apply when the next item exposes a matching track. Automatic player selection keeps fallback enabled.")
        }
    }
    
    private var supportSection: some View {
        Section("Help & Legal") {
            Button("Help") { supportDocument = .help }
            Button("Open-Source Licenses") { supportDocument = .licenses }
            Button("Terms and Privacy") { supportDocument = .terms }
            LabeledContent("Version", value: appVersionDescription)
        }
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
    
    private func save() {
        showsProviderValidationErrors = true
        guard let configuration = providerFields.build(
            id: providerManager.activeProviderID,
            kind: provider?.kind ?? .xtream
        ) else {
            providerErrorMessage = "Correct the highlighted provider fields."
            return
        }
        guard providerManager.activeProviderID == nil
                || providerRevisionState.canSave(currentRevision: providerManager.revision)
        else {
            providerErrorMessage = "Provider settings changed in another window. Review the refreshed values and save again."
            populateProviderFields()
            return
        }

        do {
            if configuration.id != nil {
                try providerManager.update(
                    provider: configuration,
                    expectedRevision: providerRevisionState.loadedRevision
                )
            } else {
                try providerManager.initialize(configuration)
            }
            populateProviderFields()
        } catch {
            providerErrorMessage = error.localizedDescription
            if case ProviderManagerError.staleProviderRevision = error {
                populateProviderFields()
            }
        }
    }

    private func resync() async {
        guard !isResyncing else { return }
        isResyncing = true
        providerErrorMessage = nil
        let result = await providerManager.resyncActiveProvider()
        isResyncing = false

        if result == .failure {
            providerErrorMessage = providerManager.session?.syncErrorMessage
                ?? "The catalog couldn’t be synced. Check the provider settings and try again."
        }
    }
    
    private func clear() {
        guard let provider else { return }
        removalConfirmation.requestRemoval(of: provider.id)
    }

    private func confirmProviderRemoval() {
        guard let providerID = removalConfirmation.confirm() else { return }

        do {
            try providerManager.delete(provider: providerID)
            providerErrorMessage = nil
            providerFields = .init(name: "", endpoint: "", username: "", password: "")
        } catch {
            providerErrorMessage = error.localizedDescription
        }
    }
}

private struct CategoryPrefixVisibilitySelector: View {
    let groupKeys: [String]
    let hiddenGroupKeys: Set<String>
    let onApply: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var draftHiddenGroupKeys: Set<String>

    init(
        groupKeys: [String],
        hiddenGroupKeys: Set<String>,
        onApply: @escaping (Set<String>) -> Void
    ) {
        self.groupKeys = groupKeys
        self.hiddenGroupKeys = hiddenGroupKeys
        self.onApply = onApply
        self._draftHiddenGroupKeys = State(initialValue: hiddenGroupKeys)
    }

    private var filteredGroupKeys: [String] {
        guard !searchText.isEmpty else { return groupKeys }

        return groupKeys.filter {
            CategoryGrouping.title(for: $0).localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Show All Prefixes") {
                        draftHiddenGroupKeys.removeAll()
                    }
                    .disabled(draftHiddenGroupKeys.isEmpty)
                }

                Section {
                    ForEach(filteredGroupKeys, id: \.self) { groupKey in
                        CategoryPrefixVisibilityRow(
                            title: CategoryGrouping.title(for: groupKey),
                            isHidden: draftHiddenGroupKeys.contains(groupKey)
                        ) {
                            toggleVisibility(for: groupKey)
                        }
                    }
                } header: {
                    Text("Detected Prefixes")
                } footer: {
                    Text("Hidden prefixes are excluded from local browse and search results for this provider.")
                }
            }
            .navigationTitle("Visible Prefixes")
#if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $searchText, prompt: "Search Prefixes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draftHiddenGroupKeys)
                    }
                }
            }
        }
    }

    private func toggleVisibility(for groupKey: String) {
        if draftHiddenGroupKeys.contains(groupKey) {
            draftHiddenGroupKeys.remove(groupKey)
        } else {
            draftHiddenGroupKeys.insert(groupKey)
        }
    }
}

private struct CategoryPrefixVisibilityRow: View {
    let title: String
    let isHidden: Bool
    let toggle: () -> Void

    private var visibilityText: String { isHidden ? "Hidden" : "Visible" }

    var body: some View {
        Button(action: toggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)

                    Text(visibilityText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isHidden ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(isHidden ? Color.secondary : Color.blue)
            }
        }
        .accessibilityLabel("\(title), \(visibilityText.lowercased())")
    }
}

private struct SettingsDestinationRow: View {
    let destination: SettingsDestination

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(systemImage: destination.systemImage, tint: destination.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(destination.title)
                    .font(.headline)

                Text(destination.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsIconBadge: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

#Preview {
    let _ = prepareDependencies { $0.defaultDatabase = try! appDatabase() }
    SettingsScreen()
        .environment(ProviderManager())
}
