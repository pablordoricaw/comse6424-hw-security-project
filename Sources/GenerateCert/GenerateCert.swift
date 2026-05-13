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
              let masterKeyIdx = args.firstIndex(of: "--master-key"),
              masterKeyIdx + 1 < args.count,
              let vendorKeyIdx = args.firstIndex(of: "--vendor-key"),
              vendorKeyIdx + 1 < args.count,
              let outIdx = args.firstIndex(of: "--out"),
              outIdx + 1 < args.count
        else {
            fputs("""
                usage: generate-cert \\
                    --fingerprint <IOPlatformUUID> \\
                    --expiration <YYYY-MM-DD> \\
                    --master-key <path/to/master_aes.key> \\
                    --vendor-key <path/to/vendor_private.pem> \\
                    --out <path/to/license.cert>
                """, stderr)
            exit(1)
        }

        let fingerprint  = args[fingerprintIdx + 1]
        let expirationStr = args[expirationIdx + 1]
        let masterKeyPath = args[masterKeyIdx + 1]
        let vendorKeyPath = args[vendorKeyIdx + 1]
        let outPath       = args[outIdx + 1]

        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            guard let parsedDate = formatter.date(from: expirationStr) else {
                exit(withError: "Invalid expiration date '\(expirationStr)'. Expected YYYY-MM-DD.")
            }
            // Advance to end of day UTC so the license is valid through 23:59:59 UTC
            let calendar = Calendar(identifier: .gregorian)
            var components = DateComponents()
            components.hour = 23
            components.minute = 59
            components.second = 59
            let expirationDate = calendar.date(byAdding: components, to: parsedDate) ?? parsedDate

            // Load the vendor Master AES key from file — same key used to
            // encrypt ast.bundle / rag.bundle at build time.
            let masterAESKey = try loadMasterAESKey(from: masterKeyPath)

            // Load vendor private signing key.
            let vendorKey = try loadVendorPrivateKey(from: vendorKeyPath)

            // Build the signed payload: key || expiration (UInt64 BE) || fingerprint (UTF-8).
            var payload = Data()
            masterAESKey.withUnsafeBytes { payload.append(contentsOf: $0) }
            var timestamp = UInt64(expirationDate.timeIntervalSince1970).bigEndian
            payload.append(contentsOf: withUnsafeBytes(of: &timestamp) { Data($0) })
            payload.append(contentsOf: fingerprint.utf8)

            let digest    = SHA256.hash(data: payload)
            let signature = try vendorKey.signature(for: digest).derRepresentation

            let cert = CertificateJSON(
                masterAESKey:      masterAESKey.withUnsafeBytes { Data($0) }.base64EncodedString(),
                expirationDate:    ISO8601DateFormatter().string(from: expirationDate),
                deviceFingerprint: fingerprint,
                vendorSignature:   signature.base64EncodedString()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = try encoder.encode(cert)

            let outURL = URL(fileURLWithPath: outPath)
            try json.write(to: outURL)
            print("✓ Certificate written to \(outPath)")

        } catch {
            exit(withError: error.localizedDescription)
        }
    }
}

private struct CertificateJSON: Encodable {
    let masterAESKey:      String
    let expirationDate:    String
    let deviceFingerprint: String
    let vendorSignature:   String
}

/// Reads a raw 32-byte AES-256 key from a binary file.
/// Generate one with: openssl rand -out master_aes.key 32
private func loadMasterAESKey(from path: String) throws -> SymmetricKey {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard data.count == 32 else {
        throw NSError(domain: "GenerateCert", code: 1,
            userInfo: [NSLocalizedDescriptionKey:
                "master_aes.key must be exactly 32 bytes (got \(data.count)). " +
                "Generate with: openssl rand -out master_aes.key 32"])
    }
    return SymmetricKey(data: data)
}

private func loadVendorPrivateKey(from path: String) throws -> P256.Signing.PrivateKey {
    let pem = try String(contentsOfFile: path, encoding: .utf8)
    return try P256.Signing.PrivateKey(pemRepresentation: pem)
}

private func exit(withError message: String) -> Never {
    fputs("error: \(message)\n", stderr)
    exit(1)
}
