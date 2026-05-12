import Testing
import Foundation
@testable import LicenseGate

@Suite("KeychainAdapter", .serialized)
struct KeychainAdapterTests {

    private let adapter = KeychainAdapter()

    init() {
        // Wipe any state left by a previous interrupted test run.
        try? adapter.delete()
    }

    private func cleanup() {
        try? adapter.delete()
    }

    @Test("store persists a token that load can retrieve")
    func storeAndLoad() throws {
        defer { cleanup() }
        let adapter = KeychainAdapter()
        let token = makeToken()

        try adapter.store(token)
        let loaded = try adapter.load()

        #expect(loaded.deviceFingerprint == token.deviceFingerprint)
        #expect(loaded.expirationDate == token.expirationDate)
        #expect(loaded.wrappedAESKey == token.wrappedAESKey)
    }

    @Test("store overwrites an existing token on re-activation")
    func storeOverwritesExisting() throws {
        defer { cleanup() }
        let adapter = KeychainAdapter()
        let first = makeToken(fingerprint: "DEVICE-AAA")
        let second = makeToken(fingerprint: "DEVICE-BBB")

        try adapter.store(first)
        try adapter.store(second)
        let loaded = try adapter.load()

        #expect(loaded.deviceFingerprint == "DEVICE-BBB")
    }

    @Test("load throws tokenNotFound when no token has been stored")
    func loadThrowsWhenNoToken() throws {
        defer { cleanup() }
        cleanup() // Ensure clean slate explicitly.
        let adapter = KeychainAdapter()

        #expect(throws: KeychainAdapterError.tokenNotFound) {
            try adapter.load()
        }
    }

    @Test("load round-trips wrappedAESKey bytes exactly")
    func loadRoundTripsWrappedKey() throws {
        defer { cleanup() }
        let adapter = KeychainAdapter()
        let keyBytes = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
        let token = makeToken(wrappedAESKey: keyBytes)

        try adapter.store(token)
        let loaded = try adapter.load()

        #expect(loaded.wrappedAESKey == keyBytes)
    }

    @Test("load round-trips expirationDate with sub-second precision")
    func loadRoundTripsExpirationDate() throws {
        defer { cleanup() }
        let adapter = KeychainAdapter()
        // JSONEncoder encodes Date as a Double (TimeInterval) — sub-second precision is preserved.
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000.123456)
        let token = makeToken(expirationDate: date)

        try adapter.store(token)
        let loaded = try adapter.load()

        #expect(loaded.expirationDate == date)
    }

    @Test("delete removes the token so load throws tokenNotFound")
    func deleteRemovesToken() throws {
        defer { cleanup() }
        let adapter = KeychainAdapter()
        try adapter.store(makeToken())
        try adapter.delete()

        #expect(throws: KeychainAdapterError.tokenNotFound) {
            try adapter.load()
        }
    }

    @Test("delete on a non-existent token does not throw")
    func deleteIsIdempotent() throws {
        defer { cleanup() }
        cleanup() // Ensure nothing is stored.
        let adapter = KeychainAdapter()

        // Calling delete when nothing exists must be a silent no-op.
        #expect(throws: Never.self) {
            try adapter.delete()
        }
    }
}

private func makeToken(
    wrappedAESKey: Data = Data(repeating: 0xAB, count: 64),
    expirationDate: Date = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365),
    fingerprint: String = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
) -> LicenseToken {
    LicenseToken(
        wrappedAESKey: wrappedAESKey,
        expirationDate: expirationDate,
        deviceFingerprint: fingerprint
    )
}
