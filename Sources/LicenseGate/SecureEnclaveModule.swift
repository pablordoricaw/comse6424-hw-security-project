import CryptoKit
import Foundation

/// Defines the hardware key operations the License Gate depends on.
/// Conformed to by `SecureEnclaveModule` (hardware) and `MockSecureEnclaveModule` (tests).
protocol SecureEnclaveModuleProtocol {
    /// Generates a new SE-backed P-256 key pair and persists the private key reference.
    /// Returns the raw bytes of the exportable public key.
    /// Call only once at activation — subsequent launches use `loadPublicKey()`.
    func generateAndStoreKeyPair() throws -> P256.KeyAgreement.PublicKey

    /// Deletes the SE key pair associated with this module.
    /// Used during test teardown and re-activation flows.
    func deleteKey() throws

    /// Loads the public key from the stored SE private key reference.
    /// Throws `SecureEnclaveModuleError.keyNotFound` if activation has not occurred.
    func loadPublicKey() throws -> P256.KeyAgreement.PublicKey

    /// Wraps (encrypts) a SymmetricKey using the SE public key via HPKE.
    /// Does not require SE hardware — uses the public key only.
    func wrap(_ masterKey: SymmetricKey, using publicKey: P256.KeyAgreement.PublicKey) throws -> Data

    /// Unwraps (decrypts) a wrapped key blob using the SE-backed private key via HPKE.
    /// Requires physical presence on the original device.
    func unwrap(_ wrappedKey: Data) throws -> SymmetricKey
}

enum SecureEnclaveModuleError: Error, LocalizedError, Equatable {
    case secureEnclaveUnavailable
    case keyGenerationFailed(underlying: Error)
    case keyDeletionFailed(status: OSStatus)
    case keyLoadFailed(underlying: Error)
    case keyNotFound
    case wrapFailed(underlying: Error)
    case unwrapFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .secureEnclaveUnavailable:
            return "This device does not have a Secure Enclave."
        case .keyGenerationFailed(let e):
            return "Secure Enclave key generation failed: \(e.localizedDescription)"
        case .keyDeletionFailed(let status):
            return "Secure Enclave key deletion failed: \(status)"
        case .keyLoadFailed(let e):
            return "Secure Enclave key load failed: \(e.localizedDescription)"
        case .keyNotFound:
            return "No Secure Enclave key found for the stored tag. Device may have changed."
        case .wrapFailed(let e):
            return "Key wrapping failed: \(e.localizedDescription)"
        case .unwrapFailed(let e):
            return "Key unwrapping failed: \(e.localizedDescription)"
        }
    }

    static func == (lhs: SecureEnclaveModuleError, rhs: SecureEnclaveModuleError) -> Bool {
            switch (lhs, rhs) {
                    case (.secureEnclaveUnavailable, .secureEnclaveUnavailable): return true
                    case (.keyGenerationFailed, .keyGenerationFailed):           return true
                    case (.keyDeletionFailed(let a), .keyDeletionFailed(let b)): return a == b
                    case (.keyLoadFailed, .keyLoadFailed):                       return true
                    case (.keyNotFound, .keyNotFound):                           return true
                    case (.wrapFailed, .wrapFailed):                             return true
                    case (.unwrapFailed, .unwrapFailed):                         return true
                    default:                                                     return false
                }
        }
}

/// The hardware-backed implementation using the macOS Secure Enclave.
/// The private key is generated inside the SE and never leaves it.
final class SecureEnclaveModule: SecureEnclaveModuleProtocol {

    // The tag used to persist and retrieve the SE private key reference.
    private let keyTag: String

    // HPKE suite: P-256 KEM, HKDF-SHA256, AES-128-GCM.
    // This is a well-established, CryptoKit-native suite compatible with SE keys.
    private let hpkeSuite = HPKE.Ciphersuite(
        kem: .P256_HKDF_SHA256,
        kdf: .HKDF_SHA256,
        aead: .AES_GCM_128
    )

    // Info and AAD strings bound to this application — prevents ciphertext
    // from being replayed across different app contexts.
    private let hpkeInfo = Data("com.closecode.licensegate.wrap".utf8)
    private let hpkeAAD  = Data("com.closecode.licensegate.aad".utf8)

    init(keyTag: String = "com.closecode.secureenclave.licensekey") {
        self.keyTag = keyTag
    }

    func generateAndStoreKeyPair() throws -> P256.KeyAgreement.PublicKey {
        guard SecureEnclave.isAvailable else {
            throw SecureEnclaveModuleError.secureEnclaveUnavailable
        }
        do {
            // dataRepresentation is a small opaque blob (not the raw private key bytes)
            // that can be stored and used to re-instantiate the SE key reference later.
            let privateKey = try SecureEnclave.P256.KeyAgreement.PrivateKey()
            try storeKeyData(privateKey.dataRepresentation)
            return privateKey.publicKey
        } catch let e as SecureEnclaveModuleError {
            throw e
        } catch {
            throw SecureEnclaveModuleError.keyGenerationFailed(underlying: error)
        }
    }

    func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureEnclaveModuleError.keyDeletionFailed(status: status)
        }
    }

    func loadPublicKey() throws -> P256.KeyAgreement.PublicKey {
        let privateKey = try loadPrivateKey()
        return privateKey.publicKey
    }

    func wrap(_ masterKey: SymmetricKey, using publicKey: P256.KeyAgreement.PublicKey) throws -> Data {
        do {
            var sender = try HPKE.Sender(
                recipientKey: publicKey,
                ciphersuite: hpkeSuite,
                info: hpkeInfo
            )
            // The plaintext is the raw bytes of the SymmetricKey.
            let plaintext = masterKey.withUnsafeBytes { Data($0) }
            let ciphertext = try sender.seal(plaintext, authenticating: hpkeAAD)

            // Prepend the encapsulated key so the receiver can complete the HPKE exchange.
            // Layout: [ encapsulatedKey (65 bytes) | ciphertext + tag ]
            return sender.encapsulatedKey + ciphertext
        } catch {
            throw SecureEnclaveModuleError.wrapFailed(underlying: error)
        }
    }

    func unwrap(_ wrappedKey: Data) throws -> SymmetricKey {
        let privateKey = try loadPrivateKey()
        do {
            // Re-split the blob back into encapsulated key and ciphertext.
            // P-256 uncompressed encapsulated key is always 65 bytes.
            let encapKeySize = 65
            guard wrappedKey.count > encapKeySize else {
                throw SecureEnclaveModuleError.unwrapFailed(
                    underlying: NSError(domain: "com.closecode", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Wrapped key blob too short."])
                )
            }
            let encapsulatedKey = wrappedKey.prefix(encapKeySize)
            let ciphertext      = wrappedKey.dropFirst(encapKeySize)

            var recipient = try HPKE.Recipient(
                privateKey: privateKey,
                ciphersuite: hpkeSuite,
                info: hpkeInfo,
                encapsulatedKey: encapsulatedKey
            )
            let plaintext = try recipient.open(ciphertext, authenticating: hpkeAAD)
            return SymmetricKey(data: plaintext)
        } catch let e as SecureEnclaveModuleError {
            throw e
        } catch {
            throw SecureEnclaveModuleError.unwrapFailed(underlying: error)
        }
    }

    // Stores the SE private key's opaque data representation in the Keychain.
    // This is NOT the raw private key bytes — it is a handle that lets CryptoKit
    // re-attach to the SE-resident key on future launches.
    private func storeKeyData(_ data: Data) throws {
        // Delete with a minimal query — kSecAttrAccessible is not valid on delete.
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag
        ]
        SecItemDelete(deleteQuery as CFDictionary)
 
        let addQuery: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrAccount as String:     keyTag,
            kSecAttrAccessible as String:  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:       data
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveModuleError.keyGenerationFailed(
                underlying: NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            )
        }
    }

    // Loads the SE private key reference from the Keychain and re-instantiates it.
    private func loadPrivateKey() throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureEnclaveModuleError.keyNotFound
        }
        do {
            return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: data)
        } catch {
            throw SecureEnclaveModuleError.keyLoadFailed(underlying: error)
        }
    }
}
