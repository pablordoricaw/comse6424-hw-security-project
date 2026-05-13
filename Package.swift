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
                "LicenseGate",
                "PromptPipeline"
            ],
            path: "Sources/CloseCode",
            resources: [
                .copy("Resources/ast.bundle"),
                .copy("Resources/rag.bundle"),
            ],
            swiftSettings: [
                    .unsafeFlags([
                        "-Xlinker", "-sectcreate",
                        "-Xlinker", "__TEXT",
                        "-Xlinker", "__entitlements",
                        "-Xlinker", "Sources/CloseCode/CloseCode.entitlements"
                    ])
                ]
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
            name: "PromptPipeline",
            dependencies: [],
            path: "Sources/PromptPipeline"
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
