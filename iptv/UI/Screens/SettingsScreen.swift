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
    private struct PrefixOption: Identifiable, Equatable {
        let prefix: String
        let matches: Int
        let categoryNames: [String]
        
        var id: String { prefix }
        
        var sampleLabel: String {
            categoryNames.prefix(2).joined(separator: ", ")
        }
    }
    
    @State private var providerFields: ProviderFields = .init(name: "", endpoint: "", username: "", password: "")
    @State private var providerErrorMessage: String?
    @State private var excludedPrefixesInput = ""
    @State private var availablePrefixOptions: [PrefixOption] = []
    @State private var selectedVisiblePrefixes: Set<String> = []
    @State private var prefixDiscoveryError: String?
  
    @Dependency(\.defaultDatabase) var database
    
    @FetchOne(Provider.where(\.isActive)) var provider: Provider?
    
    @Fetch(MediaCount(provider: nil)) var mediaCount = MediaCount.Value()
    
    @Environment(ProviderManager.self) private var providerManager
    
    @Environment(\.horizontalSizeClass) var sizeClass
   
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
        }.task(id: providerManager.session) {
            if let session = providerManager.session {
                providerFields.name = session.provider.name
                providerFields.endpoint = session.provider.endpoint.absoluteString
                providerFields.username = session.provider.username
                providerFields.password = session.provider.password
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
    
    var providerStatus: String {
        guard let session = providerManager.session else { return "Needs Setup" }
        
        switch session.sync {
            case .active: return "Syncing"
            case .success: return "All Good"
            case .failure : return "Error"
            case .idle: return "..."
        }
    }
    
    private var providerConfigurationSection: some View {
        ProviderEditorSection(
            fields: providerFields,
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
                Text("TODO")
                //                Text(excludedPrefixesSummary)
                //                    .foregroundStyle(providerManager.hasActiveProvider ? .primary : .secondary)
                //                    .multilineTextAlignment(.trailing)
            }
            
            Button("Choose Visible Prefixes") {
                print("TODO")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!providerManager.hasActiveProvider)
            
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
        guard let provider = providerFields.build(id: provider?.id) else {
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

#Preview {
    let _ = prepareDependencies { $0.defaultDatabase = try! appDatabase() }
    SettingsScreen()
        .environment(ProviderManager())
}
