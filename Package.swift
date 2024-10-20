// swift-tools-version:6.0

import PackageDescription

let package = Package(
  name: "lyricsx-tui",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.1"),
    .package(url: "https://github.com/suransea/LyricsKit", from: "1.0.0"),
    .package(url: "https://github.com/suransea/MusicPlayer.git", from: "1.0.0"),
    .package(url: "https://github.com/suransea/Termbox", from: "1.0.3"),
  ],
  targets: [
    .executableTarget(
      name: "lyricsx-tui",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        "LyricsKit",
        "MusicPlayer",
        "Termbox",
      ])
  ]
)
