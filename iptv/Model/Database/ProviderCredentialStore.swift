import Foundation
import Security

nonisolated protocol ProviderCredentialStoring: Sendable {
    func password(for reference: String) throws -> String?
    func setPassword(_ password: String, for reference: String) throws
    func deletePassword(for reference: String) throws
}

nonisolated enum ProviderCredentialStoreError: Error, LocalizedError, Equatable, Sendable {
    case invalidPasswordEncoding
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
            case .invalidPasswordEncoding:
                "The provider password could not be encoded securely."
            case let .keychainFailure(status):
                "Provider credentials are unavailable (Keychain status \(status)). Unlock this device and try again."
        }
    }
}

nonisolated struct KeychainProviderCredentialStore: ProviderCredentialStoring {
    private let service: String

    init(service: String = "com.jhoogstraat.iptv.provider-credentials") {
        self.service = service
    }

    func password(for reference: String) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            baseQuery(for: reference).merging([
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ]) { _, new in new } as CFDictionary,
            &result
        )

        switch status {
            case errSecSuccess:
                guard let data = result as? Data,
                      let password = String(data: data, encoding: .utf8)
                else {
                    throw ProviderCredentialStoreError.invalidPasswordEncoding
                }
                return password
            case errSecItemNotFound:
                return nil
            default:
                throw ProviderCredentialStoreError.keychainFailure(status)
        }
    }

    func setPassword(_ password: String, for reference: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw ProviderCredentialStoreError.invalidPasswordEncoding
        }

        let updateStatus = SecItemUpdate(
            baseQuery(for: reference) as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )

        switch updateStatus {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                var attributes = baseQuery(for: reference)
                attributes[kSecValueData] = data
                attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

                let addStatus = SecItemAdd(attributes as CFDictionary, nil)
                if addStatus == errSecDuplicateItem {
                    let retryStatus = SecItemUpdate(
                        baseQuery(for: reference) as CFDictionary,
                        [kSecValueData: data] as CFDictionary
                    )
                    guard retryStatus == errSecSuccess else {
                        throw ProviderCredentialStoreError.keychainFailure(retryStatus)
                    }
                } else if addStatus != errSecSuccess {
                    throw ProviderCredentialStoreError.keychainFailure(addStatus)
                }
            default:
                throw ProviderCredentialStoreError.keychainFailure(updateStatus)
        }
    }

    func deletePassword(for reference: String) throws {
        let status = SecItemDelete(baseQuery(for: reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderCredentialStoreError.keychainFailure(status)
        }
    }

    private func baseQuery(for reference: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: reference,
        ]
    }
}

nonisolated enum ProviderCredentialReference {
    static func make() -> String {
        "provider-\(UUID().uuidString.lowercased())"
    }

    static func migrated(providerID: Provider.ID) -> String {
        "provider-legacy-\(providerID)"
    }
}

nonisolated struct ProviderConfiguration: Hashable, Sendable {
    var id: Provider.ID?
    var kind: ProviderSourceKind
    var name: String
    var username: String
    var password: String
    var endpoint: URL
    var allowsInsecureHTTP: Bool
}
