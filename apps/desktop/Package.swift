// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Voice",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "VoiceCore"),
    .executableTarget(name: "Voice", dependencies: ["VoiceCore"]),
    .testTarget(name: "VoiceCoreTests", dependencies: ["VoiceCore"]),
  ]
)
