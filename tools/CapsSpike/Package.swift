// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CapsSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CapsSpike",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
