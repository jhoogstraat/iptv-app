//
//  SettingsScreen.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import OSLog
import SwiftUI
import SwiftData

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

@Observable
class ProviderFields {
    var name: String
    var endpoint: String
    var username: String
    var password: String
    
    var isValid: Bool {
        !name.isEmpty && !username.isEmpty && !password.isEmpty && URL(string: endpoint) != nil
    }
    
    func build() -> XtreamProvider? {
        guard isValid else { return nil }
        return XtreamProvider(name: name, endpoint: URL(string: endpoint)!, username: username, password: password, movies: [], series: [])
    }
    
    init(name: String, endpoint: String, username: String, password: String) {
        self.name = name
        self.endpoint = endpoint
        self.username = username
        self.password = password
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
    
    private let sessionManager: SessionManager
    
    @State private var providerFields: ProviderFields
    
    @State private var excludedPrefixesInput = ""
    @State private var availablePrefixOptions: [PrefixOption] = []
    @State private var selectedVisiblePrefixes: Set<String> = []
    @State private var prefixDiscoveryError: String?
    
    @Environment(\.horizontalSizeClass) var sizeClass
    
    init(sessionManager: SessionManager) {
        let fields: ProviderFields = switch sessionManager.session?.provider {
            case let xtream as XtreamProvider:
                    .init(
                        name: xtream.name,
                        endpoint: xtream.endpoint.absoluteString,
                        username: xtream.username,
                        password: xtream.password
                    )
                //            case let m3u as M3UProvider:
                //                // Example of a second provider type
                //                .init(
                //                    name: m3u.title,
                //                    endpoint: m3u.url.absoluteString,
                //                    username: "",
                //                    password: ""
                //                )
            default:
                    .init(name: "", endpoint: "", username: "", password: "")
        }
        
        self._providerFields = State(initialValue: fields)
        self.sessionManager = sessionManager
    }
    
    var body: some View {
#if os(macOS)
        macSettingsBody
            .frame(minHeight: 600)
#else
        Form {
            providerOverviewSection
            providerConfigurationSection
            librarySection
            playbackSection
            supportSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
    
#if os(macOS)
    private var macSettingsBody: some View {
        TabView {
            
            Tab("Provider", systemImage: "key.horizontal") {
                Form {
                    providerOverviewSection
                    providerConfigurationSection
                }
            }
            
            Tab("Library", systemImage: "square.grid.2x2") {
                Form {
                    librarySection
                }
            }
            
            Tab("Playback", systemImage: "play.rectangle") {
                Form {
                    playbackSection
                }
            }
            Tab("About", systemImage: "info.circle") {
                Form {
                    supportSection
                }
                
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
#endif
    
    private var providerOverviewSection: some View {
        let session = sessionManager.hasActiveSession
        
        return Section {
            let layout = sizeClass == .compact
                        ? AnyLayout(VStackLayout(spacing: 20))
                        : AnyLayout(HStackLayout(spacing: 20))

            layout {
                StatsCard(title: "Movies", value: "...", subtitle: "TODO")
                StatsCard(title: "Series", value: "...", subtitle: "TODO")
                StatsCard(title: "TV", value: "Soon", subtitle: "Live TV stats will appear here once TV support lands.")
            }
            
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Image(systemName: session ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    Text(session ? "All good" : "Needs Setup")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(session ? .green : .orange)
            }
            
            
        }
    }
    
    private var providerConfigurationSection: some View {
        let session = sessionManager.hasActiveSession
        
        return Section {
            LabeledContent("Type") {
                // TODO: Make selectable when supporting multiple provider types
                Text(sessionManager.session?.provider.type ?? "Xtream API")
                    .foregroundStyle(session ? .primary : .secondary)
                    .fixedSize()
            }
            
            TextField("Name", text: $providerFields.name, prompt: Text("Name your provider"))
                .textContentType(.username)
            
            TextField("URL", text: $providerFields.endpoint, prompt: Text("example.com or https://example.com"))
                .textContentType(.URL)
                .autocorrectionDisabled()
            
            TextField("Username", text: $providerFields.username, prompt: Text("Required"))
                .textContentType(.username)
            
            SecureField("Password", text: $providerFields.password, prompt: Text("Required"))
                .textContentType(.password)
            
            HStack {
                Spacer()
                
                Button("Save", action: save)
//                    .buttonStyle(.borderedProminent)
                    .disabled(!providerFields.isValid)
                
                Button("Reset", role: .destructive, action: clear)
                    .disabled(!sessionManager.hasActiveSession)
            }
        } header: {
            Text("Provider")
        } footer: {
            Text("Provider credentials unlock catalog loading, search, recommendations, and playback.")
        }
    }
    
    private var librarySection: some View {
        Section {
            LabeledContent("Excluded Prefixes") {
                Text("TODO")
                //                Text(excludedPrefixesSummary)
                //                    .foregroundStyle(sessionManager.hasActiveSession ? .primary : .secondary)
                //                    .multilineTextAlignment(.trailing)
            }
            
            Button("Choose Visible Prefixes") {
                print("TODO")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!sessionManager.hasActiveSession)
            
            Toggle("Group categories by language", isOn: .constant(false))
                .disabled(true)
            
            TextField(text: .constant(""), prompt: Text("Not configured")) {
                Text("Category Prefix")
            }
            .disabled(true)
            
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
            Text("All detected prefixes start visible. Deselect a prefix to hide matching categories across browse, search, and recommendations.")
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
        guard let provider = providerFields.build() else {
            fatalError("Should validate provider fields before calling save()")
        }
        sessionManager.initialize(provider: provider)
    }
    
    private func clear() {
        sessionManager.clear()
        logger.info("Provider configuration cleared.")
    }
    
    private func saveExcludedPrefixes() {
        // TODO: Implementation
        //        do {
        //            try sessionManager.saveExcludedCategoryPrefixes(excludedPrefixesInput)
        //            loadCurrentValues()
        //            statusMessage = "Excluded prefixes saved for the current provider."
        //            statusIsError = false
        //            logger.info("Excluded category prefixes saved.")
        //        } catch {
        //            statusMessage = error.localizedDescription
        //            statusIsError = true
        //            logger.error("Failed to save excluded category prefixes: \(error.localizedDescription, privacy: .public)")
        //        }
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
    }
    
    private func loadAvailablePrefixes(force: Bool) async {
        guard sessionManager.hasActiveSession else { return }
        
        await MainActor.run {
            prefixDiscoveryError = nil
        }
        
        let categories: [XtreamCategory] = []
        
        let prefixes = Self.detectedPrefixOptions(from: categories)
        availablePrefixOptions = prefixes
    }
    
    private static func detectedPrefixOptions(from categories: [XtreamCategory]) -> [PrefixOption] {
        //        var counts: [String: Int] = [:]
        //        var samples: [String: [String]] = [:]
        //
        //        for category in categories {
        //            counts[prefix, default: 0] += 1
        //            let sample = tagged.groupedDisplayName
        //            if !sample.isEmpty, !(samples[prefix] ?? []).contains(sample) {
        //                samples[prefix, default: []].append(sample)
        //            }
        //        }
        //
        //        return counts.keys.sorted().map { prefix in
        //            PrefixOption(
        //                prefix: prefix,
        //                matches: counts[prefix, default: 0],
        //                categoryNames: Array(samples[prefix, default: []].prefix(3))
        //            )
        //        }
        
        return []
    }
    
    private func synchronizeVisiblePrefixes() {
        // TODO: Implementation
        //        let excludedPrefixes = Set(sessionManager.excludedCategoryPrefixes())
        //        let availablePrefixes = Set(availablePrefixOptions.map(\.prefix))
        //
        //        if availablePrefixes.isEmpty {
        //            selectedVisiblePrefixes = []
        //            return
        //        }
        //
        //        selectedVisiblePrefixes = availablePrefixes.subtracting(excludedPrefixes)
    }
}

#Preview(traits: .previewData) {
    @Previewable @Environment(\.modelContext) var context
    SettingsScreen(sessionManager: .init(userDefaults: .standard, modelContainer: context.container))
}
