//
//  ProviderEditorView.swift
//  iptv
//
//  Created by Codex on 24.03.26.
//

import SwiftUI
import SQLiteData

@Observable
final class ProviderFields {
    var name: String
    var endpoint: String
    var username: String
    var password: String

    var isValid: Bool {
        !name.isEmpty && !username.isEmpty && !password.isEmpty && URL(string: endpoint) != nil
    }

    func build(id: Provider.ID?) -> Provider.Draft? {
        guard isValid else { return nil }
        return .init(
            id: id,
            name: name,
            username: username,
            password: password,
            endpoint: URL(string: endpoint)!,
            isActive: true
        )
    }

    init(name: String, endpoint: String, username: String, password: String) {
        self.name = name
        self.endpoint = endpoint
        self.username = username
        self.password = password
    }
}

struct ProviderEditorSection: View {
    @Bindable var fields: ProviderFields

    let isConfigured: Bool
    let isSaving: Bool
    let saveLabel: String
    let errorMessage: String?
    let onSave: () -> Void
    let onClear: (() -> Void)?

    var body: some View {
        Section {
            LabeledContent("Type") {
                Text("Xtream API")
                    .foregroundStyle(isConfigured ? .primary : .secondary)
                    .fixedSize()
            }

            TextField("Name", text: $fields.name, prompt: Text("Name your provider"))
                .textContentType(.username)

            TextField("URL", text: $fields.endpoint, prompt: Text("example.com or https://example.com"))
                .textContentType(.URL)
                .autocorrectionDisabled()

            TextField("Username", text: $fields.username, prompt: Text("Required"))
                .textContentType(.username)

            SecureField("Password", text: $fields.password, prompt: Text("Required"))
                .textContentType(.password)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button(saveLabel, action: onSave)
                    .disabled(!fields.isValid || isSaving)

                if let onClear {
                    Button("Refresh", role: .destructive, action: onClear)
                        .disabled(!isConfigured || isSaving)
                }
            }
        } header: {
            Text("Provider")
        } footer: {
            Text("Provider credentials unlock catalog loading, search, recommendations, and playback.")
        }
    }
}

struct ProviderSetupPopover: View {
    private let sessionManager: SessionManager

    @State private var providerFields = ProviderFields(name: "", endpoint: "", username: "", password: "")
    @State private var errorMessage: String?

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Add a provider to start syncing your library and unlock browsing.")
                        .foregroundStyle(.secondary)
                }

                ProviderEditorSection(
                    fields: providerFields,
                    isConfigured: false,
                    isSaving: false,
                    saveLabel: "Add Provider",
                    errorMessage: errorMessage,
                    onSave: save,
                    onClear: nil
                )
            }
            .navigationTitle("Add Provider")
#if os(macOS)
            .formStyle(.grouped)
            .padding(20)
            .frame(minWidth: 520, minHeight: 420)
#endif
        }
    }

    private func save() {
        guard let provider = providerFields.build(id: nil) else {
            errorMessage = "Please complete all provider fields."
            return
        }

        do {
            try sessionManager.initialize(provider)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
