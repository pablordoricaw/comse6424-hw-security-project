import Foundation
import CryptoKit

/// The vendor-issued artifact provided by the user at first launch.
/// Contains the plaintext Master_AES_Key and must be zeroized from memory
/// immediately after the Activation Flow completes.
struct LicenseCertificate {
    let masterAESKey: SymmetricKey      // AES-256 key that encrypts proprietary assets on disk
    let expirationDate: Date            // License validity deadline
    let deviceFingerprint: String       // IOPlatformUUID this license was issued for
    let vendorSignature: Data           // P256 signature over the canonical signed payload
}

/// The vendor's P256 signing public key, hardcoded into the binary.
/// Used exclusively to verify LicenseCertificate authenticity during Activation.
///
/// To regenerate for development:
///   openssl ecparam -name prime256v1 -genkey -noout -out vendor_private.pem
///   openssl ec -in vendor_private.pem -pubout -out vendor_public.pem
///   openssl ec -pubin -in vendor_public.pem -outform DER | base64
enum VendorPublicKey {
    /// Replace this constant with the real vendor public key before production builds.
    static let derBase64 = """
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEHmYshFUQwoutZSuX6I5L7etklCzEG63enJa80jba4q31IjYVSLNQbZZjCraTgY1a9tPCS0SJ/d7M0LMUXlnk5w==
    """

    #if DEBUG
    nonisolated(unsafe) static var _testOverride: P256.Signing.PublicKey? = nil
    #endif

    static func load() throws -> P256.Signing.PublicKey {
        #if DEBUG
        if let override = _testOverride { return override }
        #endif

        guard let der = Data(base64Encoded: derBase64, options: .ignoreUnknownCharacters) else {
            throw LicenseCertificateError.invalidVendorKey
        }
        return try P256.Signing.PublicKey(derRepresentation: der)
    }
}

extension LicenseCertificate {
    /// The canonical byte sequence the vendor signed.
    /// Field order is fixed, any change breaks all existing signatures.
    ///
    /// Layout: masterAESKey (32 bytes) || expirationDate as UInt64 Big Endian (8 bytes) || deviceFingerprint (UTF-8)
    func signedPayload() -> Data {
        var payload = Data()
        masterAESKey.withUnsafeBytes { payload.append(contentsOf: $0) }
        var timestamp = UInt64(expirationDate.timeIntervalSince1970).bigEndian
        payload.append(contentsOf: withUnsafeBytes(of: &timestamp) { Data($0) })
        payload.append(contentsOf: deviceFingerprint.utf8)
        return payload
    }

    /// Verifies that vendorSignature is a valid P256 signature over signedPayload().
    func verifyVendorSignature() throws {
        let publicKey = try VendorPublicKey.load()
        let signature = try P256.Signing.ECDSASignature(derRepresentation: vendorSignature)
        let digest = SHA256.hash(data: signedPayload())
        guard publicKey.isValidSignature(signature, for: digest) else {
            throw LicenseCertificateError.invalidVendorSignature
        }
    }
}

enum LicenseCertificateError: Error, LocalizedError {
    case invalidVendorKey
    case invalidVendorSignature

    var errorDescription: String? {
        switch self {
        case .invalidVendorKey:
            return "Vendor public key is malformed or missing."
        case .invalidVendorSignature:
            return "License Certificate signature is invalid. The certificate may be forged or tampered with."
        }
    }
}
