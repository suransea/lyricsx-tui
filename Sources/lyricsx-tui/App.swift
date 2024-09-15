import ArgumentParser
import Foundation
import MusicPlayer
import Termbox

#if os(macOS)
  typealias CurrentPlayer = MusicPlayers.SystemMedia
#elseif os(Linux)
  typealias CurrentPlayer = MusicPlayers.MPRISNowPlaying
#endif

@main
struct App: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "lyricsx-tui",
    abstract: "LyricsX in terminal UI.")

  @Option(name: .shortAndLong, help: "The hightcolor for the current line.")
  var color: Attributes = .cyan

  @Flag(help: "Disable font bold.")
  var noBold: Bool = false

  @Option(help: "Delay fix in seconds.")
  var fixDelay: TimeInterval = 0

  func run() {
    guard let player = CurrentPlayer() else {
      fatalError("Unable to connect to the music player.")
    }
    playLyrics(for: player, highlightStyle: noBold ? color : [color, .bold], fixDelay: fixDelay)
  }
}

extension Attributes: ExpressibleByArgument {
  private static let attrs: [String: Attributes] = [
    "black": .black, "white": .white, "red": .red, "green": .green, "yellow": .yellow,
    "blue": .blue, "magenta": .magenta, "cyan": .cyan,
  ]

  public init?(argument: String) {
    guard let attr = Self.attrs[argument] else { return nil }
    self = attr
  }

  public var defaultValueDescription: String { "cyan" }

  public static var allValueStrings: [String] { Array(attrs.keys) }
}
