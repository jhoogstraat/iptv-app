//
//  SettingsScreen.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import SwiftUI

struct SettingsScreen: View {
    @Environment(ProviderStore.self) private var providerStore

    @State private var baseURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section("Provider Configuration") {
                TextField("Base URL (example.com or https://example.com)", text: $baseURL)
                    .providerInputStyle()

                TextField("Username", text: $username)
                    .providerInputStyle()

                SecureField("Password", text: $password)
            }

            Section("Actions") {
                Button("Save Provider") {
                    save()
                }
                .buttonStyle(.borderedProminent)

                Button("Clear Provider") {
                    clear()
                }
                .buttonStyle(.bordered)
            }

            if let statusMessage {
                Section("Status") {
                    Text(statusMessage)
                        .foregroundStyle(statusIsError ? .red : .green)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear(perform: loadCurrentValues)
    }

    private func loadCurrentValues() {
        baseURL = providerStore.baseURLInput
        username = providerStore.username()
        password = providerStore.password()
    }

    private func save() {
        do {
            try providerStore.save(baseURL: baseURL, username: username, password: password)
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
