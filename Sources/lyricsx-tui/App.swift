import ArgumentParser
import Foundation
import MusicPlayer
import Termbox

@main
struct App: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "lyricsx-tui",
    abstract: "LyricsX in terminal UI.")

  @Option(name: .shortAndLong, help: "The hightcolor for the current line.")
  var color: Color = .cyan

  @Flag(help: "Disable font bold.")
  var noBold: Bool = false

  @Option(help: "Delay fix in seconds.")
  var fixDelay: TimeInterval = 0

  func run() throws {
    let player = try activePlayer()
    let color = Attributes(color)
    let style: Attributes = noBold ? color : [.bold, color]
    playLyrics(for: player, highlightStyle: style, fixDelay: fixDelay)
  }
}

func activePlayer() throws -> some MusicPlayerProtocol {
  #if os(macOS)
    MusicPlayers.SystemMedia()!
  #elseif os(Linux)
    try MusicPlayers.MPRISNowPlaying()
  #endif
}

enum Color: String, ExpressibleByArgument {
  case black, white, red, green, yellow, blue, magenta, cyan
}

extension Attributes {
  init(_ color: Color) {
    self =
      switch color {
      case .black: .black
      case .white: .white
      case .red: .red
      case .green: .green
      case .yellow: .yellow
      case .blue: .blue
      case .magenta: .magenta
      case .cyan: .cyan
      }
  }
}
