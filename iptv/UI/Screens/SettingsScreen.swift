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

private enum SettingsDestination: String, CaseIterable, Identifiable, Hashable {
    case provider
    case library
    case playback
    case about

    var id: Self { self }

    var title: String {
        switch self {
            case .provider: "Provider"
            case .library: "Library"
            case .playback: "Playback"
            case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
            case .provider: "Connection, credentials, and sync status"
            case .library: "Category visibility and organization"
            case .playback: "Player defaults and media behavior"
            case .about: "Version, help, and legal information"
        }
    }

    var systemImage: String {
        switch self {
            case .provider: "key.horizontal"
            case .library: "square.grid.2x2"
            case .playback: "play.rectangle"
            case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
            case .provider: .blue
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
  }
  
    let provider: Provider.ID?
    
  func fetch(_ db: Database) throws -> Value {
    try Value(
        movies: Media.where { $0.type.eq(MediaType.movie) }.fetchCount(db),
        series: Media.where { $0.type.eq(MediaType.series) }.fetchCount(db),
    )
  }
}

struct SettingsScreen: View {
    
    @State private var providerFields: ProviderFields = .init(name: "", endpoint: "", username: "", password: "")
    @State private var providerErrorMessage: String?
    @State private var hiddenCategoryGroups: Set<String> = []
    @State private var isPrefixSelectorPresented = false
    @AppStorage(CategoryPrefixVisibilityStore.revisionKey) private var prefixVisibilityRevision = 0
  
    @Dependency(\.defaultDatabase) var database
    
    @FetchOne(Provider.where(\.isActive)) var provider: Provider?
    
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
        .task(id: providerManager.session) { populateProviderFieldsFromSession() }
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
    }
    
    private func populateProviderFieldsFromSession() {
        guard let session = providerManager.session else { return }

        providerFields.name = session.provider.name
        providerFields.endpoint = session.provider.endpoint.absoluteString
        providerFields.username = session.provider.username
        providerFields.password = session.provider.password
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
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
#if os(macOS)
        .padding(20)
        .frame(minWidth: 800, minHeight: 600)
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
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
#if os(macOS)
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
#endif
    }
    


    @ViewBuilder
    private var providerOverviewSection: some View {
        let hasActiveProvider = providerManager.hasActiveProvider
        Section {
            let layout = sizeClass == .compact
                        ? AnyLayout(VStackLayout(spacing: 20))
                        : AnyLayout(HStackLayout(spacing: 20))

            layout {
                StatsCard(title: "Movies", value: "\(mediaCount.movies)", subtitle: "Categories")
                StatsCard(title: "Series", value: "\(mediaCount.series)", subtitle: "Categories")
                StatsCard(title: "TV", value: "Soon", subtitle: "Live TV stats will appear here once TV support lands.")
            }
            
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Image(systemName: hasActiveProvider ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    Text(hasActiveProvider ? "All good" : "Needs Setup")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(hasActiveProvider ? .green : .orange)
            }
        }
    }
    
    
    private var providerConfigurationSection: some View {
        ProviderEditorSection(
            fields: providerFields,
            sourceKind: provider?.kind ?? .xtream,
            isConfigured: providerManager.hasActiveProvider,
            isSaving: false,
            saveLabel: "Save",
            errorMessage: providerErrorMessage,
            onSave: save,
            onClear: clear
        )
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

            Toggle("Group categories by prefix", isOn: .constant(true))
                .disabled(true)

            Picker("Language Source", selection: .constant(LibraryLanguageSource.prefix)) {
                ForEach(LibraryLanguageSource.allCases) { source in
                    Text(source.title)
                        .tag(source)
                }
            }
            .disabled(true)
        } header: {
            Text("Library Organization")
        } footer: {
            Text("All detected prefixes start visible. Hidden prefixes are provider-scoped and are excluded from browse and search. Language filters currently use inferred category prefixes only; catalog, audio, and subtitle language metadata are not stored yet.")
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
        } header: {
            Text("Playback Defaults")
        } footer: {
            Text("Dedicated playback defaults are not exposed here yet. Today those preferences are learned from the active player session.")
        }
    }
    
    private var supportSection: some View {
        Section("Help & Legal") {
            LabeledContent("Help", value: "Coming Soon")
            LabeledContent("Licenses", value: "Coming Soon")
            LabeledContent("Terms", value: "Coming Soon")
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
        guard let provider = providerFields.build(id: provider?.id, kind: provider?.kind ?? .xtream) else {
            providerErrorMessage = "Please complete all provider fields."
            return
        }
       
        do {
            if provider.id != nil {
                try providerManager.update(provider: provider)
            } else {
                try providerManager.initialize(provider)
            }
            providerErrorMessage = nil
        } catch {
            providerErrorMessage = error.localizedDescription
        }
    }
    
    private func clear() {
        do {
            if let provider {
                try providerManager.delete(provider: provider.id)
            }
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
#if !os(macOS)
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
