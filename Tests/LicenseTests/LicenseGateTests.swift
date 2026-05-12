import Testing
import Foundation
import CryptoKit
import IOKit
@testable import LicenseGate

/// Ephemeral P256 signing key pair generated once for the entire test run.
private let testKeys: TestVendorKeys = TestVendorKeys()

private struct TestVendorKeys {
    let privateKey: P256.Signing.PrivateKey
    let publicKey: P256.Signing.PublicKey

    init() {
        privateKey = P256.Signing.PrivateKey()
        publicKey = privateKey.publicKey
    }

    func sign(_ certificate: LicenseCertificate) throws -> Data {
        let digest = SHA256.hash(data: certificate.signedPayload())
        return try privateKey.signature(for: digest).derRepresentation
    }
}

private func makeCertificate(
    masterAESKey: SymmetricKey = SymmetricKey(size: .bits256),
    expirationDate: Date = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365),
    deviceFingerprint: String = currentUUID()
) throws -> LicenseCertificate {
    let unsigned = LicenseCertificate(
        masterAESKey: masterAESKey,
        expirationDate: expirationDate,
        deviceFingerprint: deviceFingerprint,
        vendorSignature: Data()
    )
    let signature = try testKeys.sign(unsigned)
    return LicenseCertificate(
        masterAESKey: masterAESKey,
        expirationDate: expirationDate,
        deviceFingerprint: deviceFingerprint,
        vendorSignature: signature
    )
}

private func currentUUID() -> String {
    let matching = IOServiceMatching("IOPlatformExpertDevice")
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    defer { IOObjectRelease(service) }
    guard service != 0 else { return "FALLBACK-TEST-UUID" }
    let key = "IOPlatformUUID" as CFString
    let value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)
    return (value?.takeRetainedValue() as? String) ?? "FALLBACK-TEST-UUID"
}

@Suite("LicenseGate", .serialized)
struct LicenseGateTests {

    private let keychain = KeychainAdapter()
    private let se = SecureEnclaveModule()
    private let gate: LicenseGate

    init() {
        VendorPublicKey._testOverride = testKeys.publicKey
        gate = LicenseGate(keychainAdapter: keychain, secureEnclaveModule: se)

        try? keychain.delete()
        try? se.deleteKey()
    }

    private func cleanup() {
        try? keychain.delete()
        try? se.deleteKey()
    }

    @Test("activate stores a retrievable LicenseToken in the Keychain")
    func activateStoresToken() throws {
        defer { cleanup() }

        let certificate = try makeCertificate()
        try gate.activate(with: certificate)

        // The token must be retrievable by the real KeychainAdapter.
        let token = try keychain.load()
        #expect(token.deviceFingerprint == currentUUID())
    }

    @Test("activate stores the correct expirationDate in the token")
    func activateStoresExpiration() throws {
        defer { cleanup() }

        let expiration = Date(timeIntervalSinceNow: 60 * 60 * 24 * 30)
        let certificate = try makeCertificate(expirationDate: expiration)
        try gate.activate(with: certificate)

        let token = try keychain.load()
        #expect(token.expirationDate == expiration)
    }

    @Test("activate overwrites an existing token on re-activation")
    func activateOverwritesExistingToken() throws {
        defer { cleanup() }
 
        let first = try makeCertificate(expirationDate: Date(timeIntervalSinceNow: 86400))
        try gate.activate(with: first)
 
        // Fresh SE instance for re-activation — mirrors what actually happens on relaunch.
        try se.deleteKey()
        let reactivationGate = LicenseGate(
            keychainAdapter: keychain,
            secureEnclaveModule: SecureEnclaveModule(keyTag: "com.closecode.secureenclave.licensekey.test.gate")
        )
        let second = try makeCertificate(expirationDate: Date(timeIntervalSinceNow: 86400 * 60))
        try reactivationGate.activate(with: second)
 
        let token = try keychain.load()
        #expect(token.expirationDate == second.expirationDate)
    }

    @Test("activate throws when vendor signature is invalid")
    func activateRejectsInvalidSignature() throws {
        defer { cleanup() }

        let tampered = LicenseCertificate(
            masterAESKey: SymmetricKey(size: .bits256),
            expirationDate: Date(timeIntervalSinceNow: 86400),
            deviceFingerprint: currentUUID(),
            vendorSignature: Data(repeating: 0xFF, count: 64)
        )

        #expect(throws: LicenseGateError.self) {
            try gate.activate(with: tampered)
        }
        // Nothing should have been written to the Keychain.
        #expect(throws: KeychainAdapterError.tokenNotFound) {
            try keychain.load()
        }
    }

    @Test("activate throws when deviceFingerprint does not match this machine")
    func activateRejectsForeignFingerprint() throws {
        defer { cleanup() }

        let certificate = try makeCertificate(deviceFingerprint: "FOREIGN-UUID-0000")

        #expect(throws: LicenseGateError.self) {
            try gate.activate(with: certificate)
        }
        #expect(throws: KeychainAdapterError.tokenNotFound) {
            try keychain.load()
        }
    }

    @Test("activate throws when certificate fields are tampered after signing")
    func activateRejectsTamperedPayload() throws {
        defer { cleanup() }

        let original = try makeCertificate()
        let tampered = LicenseCertificate(
            masterAESKey: original.masterAESKey,
            expirationDate: original.expirationDate,
            deviceFingerprint: "TAMPERED-UUID-1234",
            vendorSignature: original.vendorSignature
        )

        #expect(throws: LicenseGateError.self) {
            try gate.activate(with: tampered)
        }
    }

    @Test("unlock returns the original masterAESKey after full activate → unlock round-trip")
    func unlockRoundTrips() throws {
        defer { cleanup() }

        let masterKey = SymmetricKey(size: .bits256)
        let certificate = try makeCertificate(masterAESKey: masterKey)
        try gate.activate(with: certificate)

        let unlocked = try gate.unlock()

        var originalBytes = [UInt8]()
        var unlockedBytes = [UInt8]()
        masterKey.withUnsafeBytes { originalBytes = Array($0) }
        unlocked.withUnsafeBytes { unlockedBytes = Array($0) }
        #expect(originalBytes == unlockedBytes)
    }

    @Test("unlock succeeds across independent gate instances (simulates app relaunch)")
    func unlockAcrossRelaunch() throws {
        defer { cleanup() }

        // First gate instance — activation (first launch).
        let masterKey = SymmetricKey(size: .bits256)
        let certificate = try makeCertificate(masterAESKey: masterKey)
        try gate.activate(with: certificate)

        let storedToken = try keychain.load()
        #expect(storedToken.deviceFingerprint == currentUUID())

        // Second gate instance sharing the same Keychain and SE key — use flow (relaunch).
        let relaunchedGate = LicenseGate(
            keychainAdapter: KeychainAdapter(tokenTag: "com.closecode.licensegate.token.test.gate"),
            secureEnclaveModule: SecureEnclaveModule(keyTag: "com.closecode.secureenclave.licensekey.test.gate")
        )
        let unlocked = try relaunchedGate.unlock()

        var originalBytes = [UInt8]()
        var unlockedBytes = [UInt8]()
        masterKey.withUnsafeBytes { originalBytes = Array($0) }
        unlocked.withUnsafeBytes { unlockedBytes = Array($0) }
        #expect(originalBytes == unlockedBytes)
    }

    @Test("unlock throws noLicenseToken when no activation has occurred")
    func unlockThrowsWithNoToken() throws {
        defer { cleanup() }
        cleanup() // Explicit clean slate.

        #expect(throws: LicenseGateError.noLicenseToken) {
            try gate.unlock()
        }
    }

    @Test("unlock throws licenseExpired when token is past its expiration date")
    func unlockThrowsWhenExpired() throws {
        defer { cleanup() }

        let expiredCertificate = try makeCertificate(
            expirationDate: Date(timeIntervalSinceNow: -1)
        )
        try gate.activate(with: expiredCertificate)

        #expect(throws: LicenseGateError.self) {
            try gate.unlock()
        }
    }

    @Test("unlock throws deviceFingerprintMismatch when token fingerprint has been tampered with")
    func unlockThrowsOnTamperedFingerprint() throws {
        defer { cleanup() }

        // Activate legitimately first to get a real wrappedAESKey into the SE.
        let certificate = try makeCertificate()
        try gate.activate(with: certificate)

        // Directly overwrite the Keychain token with a tampered fingerprint.
        let legitimate = try keychain.load()
        let tampered = LicenseToken(
            wrappedAESKey: legitimate.wrappedAESKey,
            expirationDate: legitimate.expirationDate,
            deviceFingerprint: "TAMPERED-UUID-9999"
        )
        try keychain.store(tampered)

        #expect(throws: LicenseGateError.self) {
            try gate.unlock()
        }
    }
}
