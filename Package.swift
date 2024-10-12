// swift-tools-version:5.10

import PackageDescription

let package = Package(
  name: "lyricsx-tui",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.1"),
    .package(url: "https://github.com/cx-org/CXShim", from: "0.4.0"),
    .package(url: "https://github.com/ddddxxx/LyricsKit", from: "0.11.3"),
    .package(url: "https://github.com/suransea/MusicPlayer.git", branch: "master"),
    .package(url: "https://github.com/suransea/Termbox", from: "1.0.3"),
  ],
  targets: [
    .executableTarget(
      name: "lyricsx-tui",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        "CXShim",
        "LyricsKit",
        "MusicPlayer",
        "Termbox",
      ])
  ]
)
