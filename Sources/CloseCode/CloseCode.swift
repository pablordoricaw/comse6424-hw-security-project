import Foundation
import CryptoKit

import LicenseGate
import PromptPipeline
import TUI

@main
struct CloseCode {
    static func main() {
        MainActor.assumeIsolated {
            let args = CommandLine.arguments

            if args.contains("--deactivate") {
                runDeactivation()
            // Activation Flow: closecode --activate <cert-file>
            } else if let activateIndex = args.firstIndex(of: "--activate") {
                guard activateIndex + 1 < args.count else {
                    exit(withError: "Missing certificate path after --activate.")
                }
                let certPath = args[activateIndex + 1]
                runActivation(certPath: certPath)

            // Use Flow: closecode
            } else {
                runUseFlow()
            }
        }
    }
}

private func runDeactivation() {
    do {
        let gate = LicenseGate()
        try gate.deactivate()
        print("✓ Deactivated. SE key and license token removed from this device.")
        exit(0)
    } catch {
        exit(withError: "Deactivation failed: \(error.localizedDescription)")
    }
}

private func runActivation(certPath: String) {
    do {
        let certificate = try CertificateLoader.load(from: certPath)
        let gate = LicenseGate()
        try gate.activate(with: certificate)
        print("✓ Activation successful. CloseCode is licensed on this device.")
        exit(0)
    } catch LicenseGateError.activationFailed(let msg) {
        exit(withError: "Activation failed: \(msg)")
    } catch LicenseGateError.deviceFingerprintMismatch(let expected, let actual) {
        exit(withError: "Certificate issued for device \(expected), but this device is \(actual).")
    } catch {
        exit(withError: "Activation failed: \(error.localizedDescription)")
    }
}

@MainActor
private func runUseFlow() {
    do {
        let gate = LicenseGate()
        let licenseInfo = try gate.unlock()

        // Decrypt and dlopen AST + RAG dylibs before TUI starts.
        // AssetStore holds the dlopen handles for the app's lifetime.
        let assets = AssetStore()
        try assets.load(masterAESKey: licenseInfo.masterAESKey, resourceBundle: Bundle.module)

        runTUI(licenseInfo: licenseInfo, assets: assets)

    } catch LicenseGateError.noLicenseToken {
        exit(withError: "Not activated. Run: swift run closecode --activate <certificate>")
    } catch LicenseGateError.licenseExpired(let date) {
        let formatted = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        exit(withError: "License expired on \(formatted). Please provide a new certificate.")
    } catch LicenseGateError.deviceFingerprintMismatch {
        exit(withError: "License token does not match this device. The token may have been copied.")
    } catch {
        exit(withError: "Startup failed: \(error.localizedDescription)")
    }
}

@MainActor
private func runTUI(licenseInfo: LicenseInfo, assets: AssetStore) {
    sharedLicenseInfo = licenseInfo
    sharedAssetStore = assets
    TUIRenderer.main()
}

/// Loads a LicenseCertificate from a JSON file at the given path.
private enum CertificateLoader {
    static func load(from path: String) throws -> LicenseCertificate {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LicenseCertificate.self, from: data)
    }
}

private func exit(withError message: String) -> Never {
    fputs("error: \(message)\n", stderr)
    exit(1)
}
