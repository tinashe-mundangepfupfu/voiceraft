// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VoiceRaftCore",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "VoiceRaftCore",
            targets: ["VoiceRaftCore"]
        ),
    ],
    targets: [
        .target(
            name: "VoiceRaftCore"
        ),
        .testTarget(
            name: "VoiceRaftCoreTests",
            dependencies: ["VoiceRaftCore"]
        ),
    ]
)
