//
//  ProviderStore.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import Foundation
import Observation
import Security

struct ProviderConfig: Equatable {
    let apiURL: URL
    let username: String
    let password: String
}

enum ProviderConfigError: LocalizedError {
    case missingConfiguration
    case invalidBaseURL
    case emptyUsername
    case emptyPassword
    case keychainFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Provider configuration is missing."
        case .invalidBaseURL:
            return "Please enter a valid provider base URL."
        case .emptyUsername:
            return "Username is required."
        case .emptyPassword:
            return "Password is required."
        case .keychainFailure(let details):
            return "Unable to access secure credentials storage: \(details)"
        }
    }
}

protocol KeychainStoring {
    func set(_ value: String, for key: String) throws
    func get(_ key: String) throws -> String?
    func delete(_ key: String) throws
}

struct KeychainStore: KeychainStoring {
    private let service = "com.jhoogstraat.iptv.provider"

    func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(for: key)

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw ProviderConfigError.keychainFailure("update status \(updateStatus)")
            }
        } else if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ProviderConfigError.keychainFailure("add status \(addStatus)")
            }
        } else {
            throw ProviderConfigError.keychainFailure("lookup status \(status)")
        }
    }

    func get(_ key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw ProviderConfigError.keychainFailure("read status \(status)")
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderConfigError.keychainFailure("delete status \(status)")
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

@MainActor
@Observable
final class ProviderStore {
    private enum Keys {
        static let baseURL = "provider.baseURL"
        static let username = "provider.username"
        static let password = "provider.password"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStoring

    private(set) var baseURLInput: String
    private(set) var hasConfiguration = false
    private(set) var revision = 0
    private(set) var lastValidationError: String?

    init(defaults: UserDefaults = .standard, keychain: KeychainStoring = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        self.baseURLInput = defaults.string(forKey: Keys.baseURL) ?? ""
        refresh()
    }

    func refresh() {
        do {
            hasConfiguration = (try configuration()) != nil
            lastValidationError = nil
        } catch {
            hasConfiguration = false
            lastValidationError = error.localizedDescription
        }
    }

    func username() -> String {
        (try? keychain.get(Keys.username)) ?? ""
    }

    func password() -> String {
        (try? keychain.get(Keys.password)) ?? ""
    }

    func save(baseURL: String, username: String, password: String) throws {
        let cleanedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedUsername.isEmpty else { throw ProviderConfigError.emptyUsername }
        guard !cleanedPassword.isEmpty else { throw ProviderConfigError.emptyPassword }
        _ = try normalizeAPIURL(from: cleanedBaseURL)

        defaults.set(cleanedBaseURL, forKey: Keys.baseURL)
        try keychain.set(cleanedUsername, for: Keys.username)
        try keychain.set(cleanedPassword, for: Keys.password)

        baseURLInput = cleanedBaseURL
        revision += 1
        refresh()
    }

    func clear() throws {
        defaults.removeObject(forKey: Keys.baseURL)
        try keychain.delete(Keys.username)
        try keychain.delete(Keys.password)
        baseURLInput = ""
        revision += 1
        refresh()
    }

    func configuration() throws -> ProviderConfig? {
        let baseURL = defaults.string(forKey: Keys.baseURL)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !baseURL.isEmpty else { return nil }

        guard let username = try keychain.get(Keys.username), !username.isEmpty else {
            return nil
        }

        guard let password = try keychain.get(Keys.password), !password.isEmpty else {
            return nil
        }

        let apiURL = try normalizeAPIURL(from: baseURL)
        return ProviderConfig(apiURL: apiURL, username: username, password: password)
    }

    func requiredConfiguration() throws -> ProviderConfig {
        guard let config = try configuration() else {
            throw ProviderConfigError.missingConfiguration
        }
        return config
    }

    private func normalizeAPIURL(from raw: String) throws -> URL {
        guard !raw.isEmpty else { throw ProviderConfigError.invalidBaseURL }

        let withScheme: String
        if raw.contains("://") {
            withScheme = raw
        } else {
            withScheme = "http://\(raw)"
        }

        guard var components = URLComponents(string: withScheme) else {
            throw ProviderConfigError.invalidBaseURL
        }

        if components.host == nil, let pathAsHost = components.path.split(separator: "/").first {
            components.host = String(pathAsHost)
            components.path = "/" + components.path.split(separator: "/").dropFirst().joined(separator: "/")
        }

        var path = components.path
        if path.isEmpty || path == "/" {
            path = "/player_api.php"
        } else if !path.hasSuffix("player_api.php") {
            path = path.hasSuffix("/") ? "\(path)player_api.php" : "\(path)/player_api.php"
        }
        components.path = path

        guard let url = components.url else {
            throw ProviderConfigError.invalidBaseURL
        }
        return url
    }
}
