// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Accentum",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Accentum",
            path: "Sources/Accentum"
        )
    ]
)
