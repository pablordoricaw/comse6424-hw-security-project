import Testing
import CryptoKit
import Foundation
@testable import SecureEnclave

@Suite("SecureEnclaveModule", .serialized)
struct SecureEnclaveModuleTests {

    // The same tag the module uses internally — needed for Keychain cleanup.
    private let keyTag = "com.closecode.secureenclave.licensekey"

    // Removes the SE key from the Keychain after each test so tests are isolated.
    private func cleanup() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag
        ]
        SecItemDelete(query as CFDictionary)
    }

    @Test("generateAndStoreKeyPair returns a valid P-256 public key")
    func generateAndStoreKeyPairReturnsPublicKey() throws {
        defer { cleanup() }
        let module = SecureEnclaveModule()
        let publicKey = try module.generateAndStoreKeyPair()
        // CryptoKit rawRepresentation is the compact 64-byte format (X || Y, no 0x04 prefix).
        #expect(publicKey.rawRepresentation.count == 64)
    }

    @Test("generateAndStoreKeyPair persists the key so loadPublicKey succeeds")
    func generatePersistsKey() throws {
        defer { cleanup() }
        let module = SecureEnclaveModule()
        let generated = try module.generateAndStoreKeyPair()
        let loaded = try module.loadPublicKey()
        #expect(generated.rawRepresentation == loaded.rawRepresentation)
    }

    @Test("generateAndStoreKeyPair called twice overwrites the old key cleanly")
    func generateTwiceOverwrites() throws {
        defer { cleanup() }
        let module = SecureEnclaveModule()
        let first = try module.generateAndStoreKeyPair()
        let second = try module.generateAndStoreKeyPair()
        // Two SE key pairs must be distinct.
        #expect(first.rawRepresentation != second.rawRepresentation)
        // Loaded key matches the most recent generation.
        let loaded = try module.loadPublicKey()
        #expect(loaded.rawRepresentation == second.rawRepresentation)
    }

    @Test("loadPublicKey throws keyNotFound when no key has been generated")
    func loadPublicKeyThrowsWhenNoKey() throws {
        defer { cleanup() }
        cleanup() // Ensure clean slate explicitly.
        let module = SecureEnclaveModule()
        #expect(throws: SecureEnclaveModuleError.keyNotFound) {
            try module.loadPublicKey()
        }
    }

    @Test("wrap produces a blob larger than the 64-byte encapsulated key")
    func wrapProducesBlob() throws {
        defer { cleanup() }
        let module = SecureEnclaveModule()
        let publicKey = try module.generateAndStoreKeyPair()
        let masterKey = SymmetricKey(size: .bits256)
        let wrapped = try module.wrap(masterKey, using: publicKey)
        // HPKE encapsulated key for P-256 is 65 bytes (x963 format used by HPKE internally)
        // + ciphertext (32 bytes plaintext + 16 bytes AEAD tag minimum).
        #expect(wrapped.count > 65 + 32)
    }

    @Test("wrap produces different ciphertexts for the same key (HPKE is non-deterministic)")
    func wrapIsNonDeterministic() throws {
        defer { cleanup() }
        let module = SecureEnclaveModule()
        let publicKey = try module.generateAndStoreKeyPair()
        let masterKey = SymmetricKey(size: .bits256)
        let wrapped1 = try module.wrap(masterKey, using: publicKey)
        let wrapped2 = try module.wrap(masterKey, using: publicKey)
        // Each HPKE sender uses a fresh ephemeral key — outputs must differ.
        #expect(wrapped1 != wrapped2)
    }

    @Test("unwrap recovers the original Master_AES_Key (round-trip)")
    func roundTrip() throws {
        defer { cleanup() }
        let module = SecureEnclaveModule()
        let publicKey = try module.generateAndStoreKeyPair()
        let masterKey = SymmetricKey(size: .bits256)

        let wrapped = try module.wrap(masterKey, using: publicKey)
        let unwrapped = try module.unwrap(wrapped)

        let original  = masterKey.withUnsafeBytes { Data($0) }
        let recovered = unwrapped.withUnsafeBytes { Data($0) }
        #expect(original == recovered)
    }

    @Test("unwrap fails when the wrapped blob is truncated")
    func unwrapFailsOnTruncatedBlob() throws {
        defer { cleanup() }
        let module = SecureEnclaveModule()
        let publicKey = try module.generateAndStoreKeyPair()
        let masterKey = SymmetricKey(size: .bits256)
        let wrapped = try module.wrap(masterKey, using: publicKey)

        let truncated = wrapped.prefix(32) // Far too short — missing encap key + ciphertext.
        #expect(throws: (any Error).self) {
            try module.unwrap(Data(truncated))
        }
    }

    @Test("unwrap fails when the ciphertext is corrupted")
    func unwrapFailsOnCorruptedCiphertext() throws {
        defer { cleanup() }
        let module = SecureEnclaveModule()
        let publicKey = try module.generateAndStoreKeyPair()
        let masterKey = SymmetricKey(size: .bits256)
        var wrapped = try module.wrap(masterKey, using: publicKey)

        // Flip a byte in the ciphertext region (after the 65-byte encapsulated key).
        wrapped[70] ^= 0xFF
        #expect(throws: (any Error).self) {
            try module.unwrap(wrapped)
        }
    }

    @Test("unwrap fails when no key is stored in the Keychain")
    func unwrapFailsWithNoStoredKey() throws {
        defer { cleanup() }
        let module = SecureEnclaveModule()
        let publicKey = try module.generateAndStoreKeyPair()
        let masterKey = SymmetricKey(size: .bits256)
        let wrapped = try module.wrap(masterKey, using: publicKey)

        // Simulate the Keychain entry being deleted (e.g. DoS scenario).
        cleanup()
        #expect(throws: SecureEnclaveModuleError.keyNotFound) {
            try module.unwrap(wrapped)
        }
    }
}
