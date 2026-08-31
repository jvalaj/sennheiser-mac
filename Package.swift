// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Accentum",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "Accentum",
            path: "Sources/Accentum",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
