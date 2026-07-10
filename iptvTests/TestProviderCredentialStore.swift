import Foundation

@testable import iptv
import SQLiteData

func testAppDatabase(
    credentialStore: any ProviderCredentialStoring = TestProviderCredentialStore()
) throws -> any DatabaseWriter {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("iptv-tests-\(UUID().uuidString).sqlite")
        .path
    return try appDatabase(path: path, credentialStore: credentialStore)
}

nonisolated final class TestProviderCredentialStore: ProviderCredentialStoring, @unchecked Sendable {
    enum TestError: Error {
        case inaccessible
        case forcedWriteFailure
        case forcedDeleteFailure
    }

    private let lock = NSLock()
    private var passwords: [String: String]
    private var readFailure: Error?
    private var writeFailure: Error?
    private var deleteFailure: Error?

    init(passwords: [String: String] = [:]) {
        self.passwords = passwords
    }

    func password(for reference: String) throws -> String? {
        try lock.withLock {
            if let readFailure { throw readFailure }
            return passwords[reference]
        }
    }

    func setPassword(_ password: String, for reference: String) throws {
        try lock.withLock {
            if let writeFailure { throw writeFailure }
            passwords[reference] = password
        }
    }

    func deletePassword(for reference: String) throws {
        try lock.withLock {
            if let deleteFailure { throw deleteFailure }
            passwords[reference] = nil
        }
    }

    func storedPassword(for reference: String) -> String? {
        lock.withLock { passwords[reference] }
    }

    var storedPasswordCount: Int {
        lock.withLock { passwords.count }
    }

    func removePassword(for reference: String) {
        lock.withLock { passwords[reference] = nil }
    }

    func failReads(_ error: Error? = TestError.inaccessible) {
        lock.withLock { readFailure = error }
    }

    func failWrites(_ error: Error? = TestError.forcedWriteFailure) {
        lock.withLock { writeFailure = error }
    }

    func failDeletes(_ error: Error? = TestError.forcedDeleteFailure) {
        lock.withLock { deleteFailure = error }
    }
}
