//
//  ProviderEditorView.swift
//  iptv
//
//  Created by Codex on 24.03.26.
//

import SwiftUI
import SQLiteData
import xtream_swift

@Observable
final class ProviderFields {
    var name: String
    var endpoint: String
    var username: String
    var password: String

    var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty,
              !trimmedUsername.isEmpty,
              !trimmedPassword.isEmpty
        else {
            return false
        }

        return (try? XtreamEndpoint.normalizeBaseURL(endpoint)) != nil
    }

    func build(id: Provider.ID?, kind: ProviderSourceKind) -> Provider.Draft? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty,
              !trimmedUsername.isEmpty,
              !trimmedPassword.isEmpty,
              let normalizedEndpoint = try? XtreamEndpoint.normalizeBaseURL(endpoint)
        else {
            return nil
        }

        return .init(
            id: id,
            kind: kind,
            name: trimmedName,
            username: trimmedUsername,
            password: trimmedPassword,
            endpoint: normalizedEndpoint,
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

    let sourceKind: ProviderSourceKind
    let isConfigured: Bool
    let isSaving: Bool
    let saveLabel: String
    let errorMessage: String?
    var saveAccessibilityIdentifier = "onboarding.provider.save"
    let onSave: () -> Void
    let onClear: (() -> Void)?

    var body: some View {
        Section {
            TextField("Name", text: $fields.name, prompt: Text("Name your provider"))
                .textContentType(.username)
                .accessibilityIdentifier("onboarding.provider.name")

            TextField("URL", text: $fields.endpoint, prompt: Text("example.com or https://example.com"))
                .textContentType(.URL)
                .autocorrectionDisabled()
                .accessibilityIdentifier("onboarding.provider.url")

            TextField("Username", text: $fields.username, prompt: Text("Required"))
                .textContentType(.username)
                .accessibilityIdentifier("onboarding.provider.username")

            SecureField("Password", text: $fields.password, prompt: Text("Required"))
                .textContentType(.password)
                .accessibilityIdentifier("onboarding.provider.password")

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button(saveLabel, action: onSave)
                    .disabled(!fields.isValid || isSaving)
                    .accessibilityIdentifier(saveAccessibilityIdentifier)

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
