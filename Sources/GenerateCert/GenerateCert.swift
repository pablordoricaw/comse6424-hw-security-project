import Foundation
import CryptoKit

@main
struct GenerateCert {
    static func main() {
        let args = CommandLine.arguments

        guard let fingerprintIdx = args.firstIndex(of: "--fingerprint"),
              fingerprintIdx + 1 < args.count,
              let expirationIdx = args.firstIndex(of: "--expiration"),
              expirationIdx + 1 < args.count,
              let vendorKeyIdx = args.firstIndex(of: "--vendor-key"),
              vendorKeyIdx + 1 < args.count,
              let outIdx = args.firstIndex(of: "--out"),
              outIdx + 1 < args.count
        else {
            fputs("""
                usage: generate-cert \\
                    --fingerprint <IOPlatformUUID> \\
                    --expiration <YYYY-MM-DD> \\
                    --vendor-key <path/to/vendor_private.pem> \\
                    --out <path/to/license.cert>
                """, stderr)
            exit(1)
        }

        let fingerprint = args[fingerprintIdx + 1]
        let expirationStr = args[expirationIdx + 1]
        let vendorKeyPath = args[vendorKeyIdx + 1]
        let outPath = args[outIdx + 1]

        do {
            // Parse expiration date.
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            guard let expirationDate = formatter.date(from: expirationStr) else {
                exit(withError: "Invalid expiration date '\(expirationStr)'. Expected YYYY-MM-DD.")
            }

            // Load vendor private key from PEM.
            let vendorKey = try loadVendorPrivateKey(from: vendorKeyPath)

            // Generate a fresh Master AES-256 key.
            let masterAESKey = SymmetricKey(size: .bits256)

            // Build the signed payload: key || expiration (UInt64 BE) || fingerprint (UTF-8).
            var payload = Data()
            masterAESKey.withUnsafeBytes { payload.append(contentsOf: $0) }
            var timestamp = UInt64(expirationDate.timeIntervalSince1970).bigEndian
            payload.append(contentsOf: withUnsafeBytes(of: &timestamp) { Data($0) })
            payload.append(contentsOf: fingerprint.utf8)

            // Sign with vendor private key.
            let digest = SHA256.hash(data: payload)
            let signature = try vendorKey.signature(for: digest).derRepresentation

            // Encode certificate to JSON.
            let cert = CertificateJSON(
                masterAESKey: masterAESKey.withUnsafeBytes { Data($0) }.base64EncodedString(),
                expirationDate: ISO8601DateFormatter().string(from: expirationDate),
                deviceFingerprint: fingerprint,
                vendorSignature: signature.base64EncodedString()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = try encoder.encode(cert)

            // Write to output file.
            let outURL = URL(fileURLWithPath: outPath)
            try json.write(to: outURL)
            print("✓ Certificate written to \(outPath)")

        } catch {
            exit(withError: error.localizedDescription)
        }
    }
}

/// Mirrors LicenseCertificate's Codable layout exactly.
/// Kept local so generate-cert has zero dependency on LicenseGate.
private struct CertificateJSON: Encodable {
    let masterAESKey: String       // base64-encoded raw key bytes
    let expirationDate: String     // ISO 8601
    let deviceFingerprint: String
    let vendorSignature: String    // base64-encoded DER signature
}

private func loadVendorPrivateKey(from path: String) throws -> P256.Signing.PrivateKey {
    let pem = try String(contentsOfFile: path, encoding: .utf8)
    return try P256.Signing.PrivateKey(pemRepresentation: pem)
}

private func exit(withError message: String) -> Never {
    fputs("error: \(message)\n", stderr)
    exit(1)
}
