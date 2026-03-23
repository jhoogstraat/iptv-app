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

@Observable
class ProviderFields {
    var name: String
    var endpoint: String
    var username: String
    var password: String
    
    var isValid: Bool {
        !name.isEmpty && !username.isEmpty && !password.isEmpty && URL(string: endpoint) != nil
    }
    
    func build() -> Provider.Draft? {
        guard isValid else { return nil }
        return .init(id: nil, name: name, username: username, password: password, endpoint: URL(string: endpoint)!, isActive: true)
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
        let fields = if let provider = sessionManager.session?.provider {
            ProviderFields(
                name: provider.name,
                endpoint: provider.endpoint.absoluteString,
                username: provider.username,
                password: provider.password
            )
        } else {
            ProviderFields(name: "", endpoint: "", username: "", password: "")
        }
        
        self._providerFields = State(initialValue: fields)
        self.sessionManager = sessionManager
    }
    
    var body: some View {
#if os(macOS)
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
        .frame(minWidth: 800, minHeight: 600)
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
    
    @ViewBuilder
    private var providerOverviewSection: some View {
        let session = sessionManager.hasActiveSession
        Section {
            let layout = sizeClass == .compact
                        ? AnyLayout(VStackLayout(spacing: 20))
                        : AnyLayout(HStackLayout(spacing: 20))

            layout {
                StatsCard(title: "Movies", value: "...", subtitle: syncDescription(sessionManager.session?.syncManager.movieSync))
                StatsCard(title: "Series", value: "...", subtitle: syncDescription(sessionManager.session?.syncManager.seriesSync))
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
    
    var providerStatus: String {
        if !sessionManager.hasActiveSession { return "Needs Setup" }
        if sessionManager.session?.syncManager.movieSync == .active || sessionManager.session?.syncManager.seriesSync == .active { return "Syncing" }
        if sessionManager.session?.syncManager.movieSync == .success && sessionManager.session?.syncManager.seriesSync == .success { return "All Good" }
        if sessionManager.session?.syncManager.movieSync == .failure || sessionManager.session?.syncManager.seriesSync == .failure { return "Error" }
        return "All Good!"
    }
    
    func syncDescription(_ state: SyncManager.SyncState?) -> String {
        if let state {
            switch state {
                case .idle: return "Not syncing"
                case .active: return "Syncing"
                case .failure: return "Failed"
                case .success: return "Synced"
            }
        } else {
            return "..."
        }
    }
    
    private var providerConfigurationSection: some View {
        let session = sessionManager.hasActiveSession
        
        return Section {
            LabeledContent("Type") {
                Text("Xtream API")
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
                
                Button("Refresh", role: .destructive, action: clear)
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
            print("TODO")
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
        sessionManager.initialize(provider)
    }
    
    private func clear() {
        try? sessionManager.clear()
    }
}

#Preview {
    SettingsScreen(sessionManager: .init())
}
