// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "lyricsx-cli",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.3.1")),
        .package(url: "https://github.com/ddddxxx/LyricsKit", .upToNextMinor(from: "0.11.3")),
        .package(url: "https://github.com/ddddxxx/MusicPlayer", .upToNextMinor(from: "0.8.3")),
        .package(url: "https://github.com/suransea/Termbox", .upToNextMinor(from: "1.0.2")),
    ],
    targets: [
        .executableTarget(
            name: "lyricsx-cli",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "LyricsKit",
                "MusicPlayer",
                "Termbox",
            ]),
        .testTarget(
            name: "lyricsx-cli-tests",
            dependencies: ["lyricsx-cli"]),
    ]
)
