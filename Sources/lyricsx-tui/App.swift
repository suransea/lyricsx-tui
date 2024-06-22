import ArgumentParser
import Combine
import Foundation
import MusicPlayer
import Termbox

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
    runApp(foreground: noBold ? color : [color, .bold], fixDelay: fixDelay)
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

#if os(macOS)
  typealias CurrentPlayer = MusicPlayers.SystemMedia
#elseif os(Linux)
  typealias CurrentPlayer = MusicPlayers.MPRISNowPlaying
#endif

private func runApp(foreground: Attributes, fixDelay: TimeInterval = 0) {
  guard let player = CurrentPlayer() else {
    fatalError("Unable to connect to the music player.")
  }
  do { try Termbox.initialize() } catch {
    fatalError("\(error)")
  }

  var cancelBag = [AnyCancellable]()
  let terminalEvents = terminalEvents().share()

  let cancelPlay = playLyrics(
    for: player, on: .main,
    foreground: foreground, fixDelay: fixDelay,
    terminalEvents: terminalEvents)

  terminalEvents
    .receive(on: DispatchQueue.main)
    .sink { event in
      switch event {
      case .character(modifier: .none, value: "q"):
        cancelBag = []
        cancelPlay()
        Termbox.shutdown()
        exit(0)
        break
      case .key(modifier: .none, value: .space):
        player.playPause()
        break
      case .character(modifier: .none, value: ","):
        player.skipToPreviousItem()
        break
      case .character(modifier: .none, value: "."):
        player.skipToNextItem()
        break
      default:
        break
      }
    }
    .store(in: &cancelBag)

  #if os(Linux)
    Thread.detachNewThread {
      Thread.current.name = "GMainLoop"
      GRunLoop.main.run()
    }
  #endif
  RunLoop.main.run()

  Termbox.shutdown()
}
