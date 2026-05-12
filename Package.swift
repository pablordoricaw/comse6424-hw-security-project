// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "CloseCode",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/phranck/TUIkit.git", from: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "get-fingerprint",
            path: "Sources/GetFingerprint",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "generate-cert",
            path: "Sources/GenerateCert",
        ),
        .executableTarget(
            name: "closecode",
            dependencies: [
                "TUI",
                "LicenseGate"
            ],
            path: "Sources/CloseCode",
        ),
        .target(
            name: "TUI",
            dependencies: [
                "TUIkit",
                "LicenseGate"
            ],
            path: "Sources/TUI"
        ),
        .target(
            name: "LicenseGate",
            path: "Sources/LicenseGate",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "LicenseTests",
            dependencies: [
                "LicenseGate"
            ],
            path: "Tests/LicenseTests",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
