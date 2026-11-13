// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Voice",
  platforms: [.macOS("14.2")],
  targets: [
    .target(name: "VoiceCore"),
    .executableTarget(name: "Voice", dependencies: ["VoiceCore"]),
    .testTarget(name: "VoiceCoreTests", dependencies: ["VoiceCore"]),
  ]
)
