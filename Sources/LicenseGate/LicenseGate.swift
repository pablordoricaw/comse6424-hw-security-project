import Foundation
import CryptoKit
import IOKit

public struct LicenseInfo {
    public let masterAESKey: SymmetricKey
    public let expirationDate: Date
    public let deviceFingerprint: String
}

public protocol LicenseGateProtocol {
    func activate(with certificate: LicenseCertificate) throws
    func deactivate() throws
    func unlock() throws -> LicenseInfo
}

public enum LicenseGateError: Error, LocalizedError, Equatable {
    case deviceFingerprintMismatch(expected: String, actual: String)
    case licenseExpired(expiredOn: Date)
    case noLicenseToken
    case activationFailed(underlying: String)
    case unlockFailed(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .deviceFingerprintMismatch(let expected, let actual):
            return "License was issued for device \(expected) but this device is \(actual)."
        case .licenseExpired(let date):
            let formatted = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
            return "License expired on \(formatted). Please provide a new License Certificate."
        case .noLicenseToken:
            return "No License Token found. Please activate CloseCode with a valid License Certificate."
        case .activationFailed(let msg):
            return "Activation failed: \(msg)"
        case .unlockFailed(let msg):
            return "Unlock failed: \(msg)"
        }
    }

    public static func == (lhs: LicenseGateError, rhs: LicenseGateError) -> Bool {
        switch (lhs, rhs) {
        case (.deviceFingerprintMismatch, .deviceFingerprintMismatch): return true
        case (.licenseExpired, .licenseExpired):                       return true
        case (.noLicenseToken, .noLicenseToken):                       return true
        case (.activationFailed, .activationFailed):                   return true
        case (.unlockFailed, .unlockFailed):                           return true
        default:                                                       return false
        }
    }
}

private func readIOPlatformUUID() -> String? {
    let matching = IOServiceMatching("IOPlatformExpertDevice")
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    defer { IOObjectRelease(service) }
    guard service != 0 else { return nil }
    let key = "IOPlatformUUID" as CFString
    let value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)
    return value?.takeRetainedValue() as? String
}

public final class LicenseGate: LicenseGateProtocol {

    private let keychainAdapter: KeychainAdapterProtocol
    private let secureEnclaveModule: SecureEnclaveModuleProtocol

    public init () {
        self.keychainAdapter = KeychainAdapter()
        self.secureEnclaveModule = SecureEnclaveModule()
    }

    init(
        keychainAdapter: KeychainAdapterProtocol,
        secureEnclaveModule: SecureEnclaveModuleProtocol
    ) {
        self.keychainAdapter = keychainAdapter
        self.secureEnclaveModule = secureEnclaveModule
    }

    public func activate(with certificate: LicenseCertificate) throws {
        do {
            // Step 1: Verify vendor signature.
            try certificate.verifyVendorSignature()

            // Step 2: Verify device fingerprint.
            try verifyDeviceFingerprint(against: certificate.deviceFingerprint)

            // Step 3: Generate SE key pair and returns the public key immediately.
            let publicKey = try secureEnclaveModule.generateAndStoreKeyPair()

            // Step 4: Wrap the Master_AES_Key using the SE public key.
            let wrappedKey = try secureEnclaveModule.wrap(
                certificate.masterAESKey,
                using: publicKey
            )

            // Step 5: Construct and persist the License Token.
            let token = LicenseToken(
                wrappedAESKey: wrappedKey,
                expirationDate: certificate.expirationDate,
                deviceFingerprint: certificate.deviceFingerprint
            )
            try keychainAdapter.store(token)

            // Step 6: certificate goes out of scope, CryptoKit zeroes masterAESKey.

        } catch let error as LicenseGateError {
            throw error
        } catch {
            throw LicenseGateError.activationFailed(underlying: error.localizedDescription)
        }
    }
 
    public func deactivate() throws {
        do {
            try secureEnclaveModule.deleteKey()
            try keychainAdapter.delete()
        } catch {
            throw LicenseGateError.activationFailed(underlying: error.localizedDescription)
        }
    }

    public func unlock() throws -> LicenseInfo {
        do {
            // Step 1: Retrieve the stored License Token.
            let token = try keychainAdapter.load()

            // Step 2: Verify device fingerprint.
            try verifyDeviceFingerprint(against: token.deviceFingerprint)

            // Step 3: Check expiration against local clock.
            try verifyExpiration(of: token)

            // Step 4: Unwrap the Master_AES_Key via the SE private key.
            let masterAESKey = try secureEnclaveModule.unwrap(token.wrappedAESKey)

            return LicenseInfo(
                masterAESKey: masterAESKey,
                expirationDate: token.expirationDate,
                deviceFingerprint: token.deviceFingerprint
            )
        } catch let error as LicenseGateError {
            throw error
        } catch let error as KeychainAdapterError where error == .tokenNotFound {
            throw LicenseGateError.noLicenseToken
        } catch {
            throw LicenseGateError.unlockFailed(underlying: error.localizedDescription)
        }
    }

    private func verifyDeviceFingerprint(against expected: String) throws {
        guard let actual = readIOPlatformUUID() else {
            throw LicenseGateError.deviceFingerprintMismatch(expected: expected, actual: "<unreadable>")
        }
        guard actual == expected else {
            throw LicenseGateError.deviceFingerprintMismatch(expected: expected, actual: actual)
        }
    }

    private func verifyExpiration(of token: LicenseToken) throws {
        if Date() > token.expirationDate {
            throw LicenseGateError.licenseExpired(expiredOn: token.expirationDate)
        }
    }
}
