//
//  ProviderEditorView.swift
//  iptv
//
//  Created by Codex on 24.03.26.
//

import SwiftUI
import SQLiteData
import xtream_swift

struct ProviderFieldValidation: Equatable {
    var name: String?
    var endpoint: String?
    var username: String?
    var password: String?

    var isValid: Bool {
        name == nil && endpoint == nil && username == nil && password == nil
    }
}

@Observable
final class ProviderFields {
    var name: String
    var endpoint: String
    var username: String
    var password: String
    var allowsInsecureHTTP: Bool

    var isExplicitlyInsecure: Bool {
        (try? ProviderEndpointPolicy.normalize(endpoint).scheme?.lowercased()) == "http"
    }

    var validation: ProviderFieldValidation {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEndpoint = try? ProviderEndpointPolicy.normalize(endpoint)

        var validation = ProviderFieldValidation()
        if trimmedName.isEmpty {
            validation.name = "Enter a provider name."
        }
        if endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validation.endpoint = "Enter the provider URL."
        } else if normalizedEndpoint == nil {
            validation.endpoint = "Enter a valid HTTP or HTTPS URL without embedded credentials."
        } else if normalizedEndpoint?.scheme?.lowercased() == "http", !allowsInsecureHTTP {
            validation.endpoint = "Explicitly allow insecure HTTP to use this provider."
        }
        if trimmedUsername.isEmpty {
            validation.username = "Enter the provider username."
        }
        if password.isEmpty {
            validation.password = "Enter the provider password."
        }
        return validation
    }

    var isValid: Bool {
        validation.isValid
    }

    func build(id: Provider.ID?, kind: ProviderSourceKind) -> ProviderConfiguration? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard validation.isValid,
              let normalizedEndpoint = try? ProviderEndpointPolicy.normalize(endpoint)
        else {
            return nil
        }

        let isInsecure = normalizedEndpoint.scheme?.lowercased() == "http"
        guard !isInsecure || allowsInsecureHTTP else { return nil }

        return .init(
            id: id,
            kind: kind,
            name: trimmedName,
            username: trimmedUsername,
            password: password,
            endpoint: normalizedEndpoint,
            allowsInsecureHTTP: isInsecure && allowsInsecureHTTP
        )
    }

    init(
        name: String,
        endpoint: String,
        username: String,
        password: String,
        allowsInsecureHTTP: Bool = false
    ) {
        self.name = name
        self.endpoint = endpoint
        self.username = username
        self.password = password
        self.allowsInsecureHTTP = allowsInsecureHTTP
    }
}

nonisolated enum ProviderEndpointPolicy {
    static func normalize(_ endpoint: String) throws -> URL {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointWithScheme = trimmedEndpoint.contains("://")
            ? trimmedEndpoint
            : "https://\(trimmedEndpoint)"
        let normalizedEndpoint = try XtreamEndpoint.normalizeBaseURL(endpointWithScheme)

        guard let scheme = normalizedEndpoint.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              normalizedEndpoint.user == nil,
              normalizedEndpoint.password == nil
        else {
            throw ProviderEndpointPolicyError.unsupportedEndpoint
        }

        return normalizedEndpoint
    }
}

nonisolated enum ProviderEndpointPolicyError: Error {
    case unsupportedEndpoint
}

struct ProviderEditorSection: View {
    @Bindable var fields: ProviderFields

    let sourceKind: ProviderSourceKind
    let isConfigured: Bool
    let isSaving: Bool
    let saveLabel: String
    let errorMessage: String?
    var showsValidationErrors = false
    var saveAccessibilityIdentifier = "onboarding.provider.save"
    let onSave: () -> Void
    let onRemove: (() -> Void)?

    var body: some View {
        Section {
            TextField("Name", text: $fields.name, prompt: Text("Name your provider"))
                .textContentType(.username)
                .accessibilityIdentifier("onboarding.provider.name")
            validationMessage(fields.validation.name, field: "name")

            TextField("URL", text: $fields.endpoint, prompt: Text("example.com (uses HTTPS)"))
                .textContentType(.URL)
                .autocorrectionDisabled()
                .accessibilityIdentifier("onboarding.provider.url")
            validationMessage(fields.validation.endpoint, field: "url")

            TextField("Username", text: $fields.username, prompt: Text("Required"))
                .textContentType(.username)
                .accessibilityIdentifier("onboarding.provider.username")
            validationMessage(fields.validation.username, field: "username")

            SecureField("Password", text: $fields.password, prompt: Text("Required"))
                .textContentType(.password)
                .accessibilityIdentifier("onboarding.provider.password")
            validationMessage(fields.validation.password, field: "password")

            if fields.isExplicitlyInsecure {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Insecure HTTP connection", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Text("HTTP sends your provider username and password without transport encryption. Only continue if you trust this network and the provider cannot use HTTPS.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle("Allow insecure HTTP for this provider", isOn: $fields.allowsInsecureHTTP)
                        .accessibilityIdentifier("onboarding.provider.allowInsecureHTTP")
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button(saveLabel, action: onSave)
                    .disabled(isSaving)
                    .accessibilityIdentifier(saveAccessibilityIdentifier)

                if let onRemove {
                    Button("Remove Provider", role: .destructive, action: onRemove)
                        .disabled(!isConfigured || isSaving)
                        .accessibilityIdentifier("settings.provider.remove")
                }
            }
        } header: {
            Text("Provider")
        } footer: {
            Text("Passwords are stored in Keychain. Provider credentials unlock catalog loading, search, recommendations, and playback.")
        }
    }

    @ViewBuilder
    private func validationMessage(_ message: String?, field: String) -> some View {
        if showsValidationErrors, let message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityLabel("\(field.capitalized) error: \(message)")
                .accessibilityIdentifier("onboarding.provider.\(field).error")
        }
    }
}
