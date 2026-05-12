import Foundation
import Security

/// The persisted state that survives between CloseCode launches.
/// Stored as a single JSON blob in the login Keychain.
struct LicenseToken: Codable {
    let wrappedAESKey: Data
    let expirationDate: Date
    let deviceFingerprint: String
}

enum KeychainAdapterError: Error, LocalizedError, Equatable {
    case tokenNotFound
    case encodingFailed(underlying: String)
    case decodingFailed(underlying: String)
    case storeFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .tokenNotFound:
            return "No License Token found in the Keychain. Device may not be activated."
        case .encodingFailed(let msg):
            return "Failed to encode License Token: \(msg)"
        case .decodingFailed(let msg):
            return "Failed to decode License Token: \(msg)"
        case .storeFailed(let status):
            return "Keychain store failed with status: \(status)"
        case .deleteFailed(let status):
            return "Keychain delete failed with status: \(status)"
        }
    }

    static func == (lhs: KeychainAdapterError, rhs: KeychainAdapterError) -> Bool {
        switch (lhs, rhs) {
        case (.tokenNotFound, .tokenNotFound):               return true
        case (.encodingFailed, .encodingFailed):             return true
        case (.decodingFailed, .decodingFailed):             return true
        case (.storeFailed(let a), .storeFailed(let b)):     return a == b
        case (.deleteFailed(let a), .deleteFailed(let b)):   return a == b
        default:                                             return false
        }
    }
}

protocol KeychainAdapterProtocol {
    /// Persists the License Token to the login Keychain.
    /// Overwrites any existing token (handles re-activation).
    func store(_ token: LicenseToken) throws

    /// Retrieves and decodes the License Token from the login Keychain.
    /// Throws `KeychainAdapterError.tokenNotFound` if no token exists.
    func load() throws -> LicenseToken

    /// Deletes the License Token from the login Keychain.
    /// Used during license revocation and test teardown.
    func delete() throws
}

final class KeychainAdapter: KeychainAdapterProtocol {

    private let tokenTag = "com.closecode.licensegate.token"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func store(_ token: LicenseToken) throws {
        let data: Data
        do {
            data = try encoder.encode(token)
        } catch {
            throw KeychainAdapterError.encodingFailed(underlying: error.localizedDescription)
        }

        // ? to ignore error deleting License Token on activation
        try? delete()

        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrAccount as String:    tokenTag,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:      data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainAdapterError.storeFailed(status: status)
        }
    }

    func load() throws -> LicenseToken {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: tokenTag,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainAdapterError.tokenNotFound
        }
        do {
            return try decoder.decode(LicenseToken.self, from: data)
        } catch {
            throw KeychainAdapterError.decodingFailed(underlying: error.localizedDescription)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: tokenTag
        ]
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound is acceptable — deleting a non-existent item is a no-op.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainAdapterError.deleteFailed(status: status)
        }
    }
}
