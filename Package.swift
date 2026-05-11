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
                "SecureEnclave"
            ]
        ),
        .target(
            name: "SecureEnclave",
            path: "Sources/SecureEnclave"
        ),
        .testTarget(
            name: "LicenseTests",
            dependencies: ["SecureEnclave"],
            path: "Tests/LicenseTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
