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
            name: "CloseCode",
            dependencies: [
                "TUIkit",
                "LicenseGate"
            ]
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
