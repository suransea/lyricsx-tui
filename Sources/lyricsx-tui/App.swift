import ArgumentParser
import Combine
import Foundation
import LyricsCore
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
  let playingLyrics = CurrentValueSubject<Lyrics?, Never>(nil)
  var currentIndex = -1
  var fetchedLyrics: [Lyrics] = []
  var lyricsIndex = -1

  playingLyrics
    .combineLatest(player.playbackStateWillChange.prepend(.stopped))
    .map { lyrics, state in
      updateBottomBar(
        state: state, lyric: lyrics, index: lyricsIndex, count: fetchedLyrics.count)
      if let lyrics = lyrics {
        currentIndex = index(of: state.time, of: lyrics.lines) - 1
        updateLyricArea(lines: lyrics.lines, index: currentIndex, foreground: foreground)
        if state.isPlaying {
          Termbox.present()
          return timedIndices(
            of: lyrics.lines, on: .main, with: player, fixDelay: fixDelay
          )
          .eraseToAnyPublisher()
        }
      } else {
        currentIndex = -1
        clearLyricArea()
      }
      Termbox.present()
      return Empty().eraseToAnyPublisher()
    }
    .switchToLatest()
    .receive(on: DispatchQueue.main)
    .sink { index in
      currentIndex = index
      guard let lyrics = playingLyrics.value else { return }
      updateLyricArea(lines: lyrics.lines, index: index, foreground: foreground)
      Termbox.present()
    }
    .store(in: &cancelBag)

  player.currentTrackWillChange
    .prepend(nil)
    .handleEvents(receiveOutput: { track in
      fetchedLyrics = []
      playingLyrics.send(nil)
      updateTopBar(track: track)
      Termbox.present()
    })
    .flatMap { track in
      track.map {
        lyrics(of: $0)
          .handleEvents(receiveOutput: { lyrics in
            fetchedLyrics = lyrics
            lyricsIndex = 0
          })
          .map(\.first)
          .eraseToAnyPublisher()
      } ?? Just(nil).eraseToAnyPublisher()
    }
    .sink { playingLyrics.send($0) }
    .store(in: &cancelBag)

  let reloadLyrics = {
    guard let track = player.currentTrack else { return }
    updateBottomBar(state: player.playbackState, source: "Reloading...")
    Termbox.present()
    lyrics(of: track)
      .handleEvents(receiveOutput: { lyrics in
        fetchedLyrics = lyrics
        lyricsIndex = 0
      })
      .map(\.first)
      .sink { playingLyrics.send($0) }
      .store(in: &cancelBag)
  }

  let forceUpdate = {
    updateTopBar(track: player.currentTrack)
    if let lyrics = playingLyrics.value {
      updateLyricArea(lines: lyrics.lines, index: currentIndex, foreground: foreground)
    } else {
      clearLyricArea()
    }
    updateBottomBar(
      state: player.playbackState, lyric: playingLyrics.value, index: lyricsIndex,
      count: fetchedLyrics.count)
    Termbox.present()
  }

  terminalEvents(on: DispatchQueue(label: "TerminalEvents"))
    .receive(on: DispatchQueue.main)
    .sink { event in
      switch event {
      case .character(modifier: .none, value: "q"):
        cancelBag = []
        Termbox.shutdown()
        exit(0)
        break
      case .character(modifier: .none, value: "r"):
        reloadLyrics()
        break
      case .resize(width: _, height: _):
        forceUpdate()
        break
      case .key(modifier: .none, value: .space):
        player.playPause()
        break
      case .key(modifier: .none, value: .arrowUp):
        if !fetchedLyrics.isEmpty {
          lyricsIndex -= 1
          if lyricsIndex < 0 {
            lyricsIndex = fetchedLyrics.count - 1
          }
          playingLyrics.send(fetchedLyrics[lyricsIndex])
        }
        break
      case .key(modifier: .none, value: .arrowDown):
        if !fetchedLyrics.isEmpty {
          lyricsIndex += 1
          if lyricsIndex >= fetchedLyrics.count {
            lyricsIndex = 0
          }
          playingLyrics.send(fetchedLyrics[lyricsIndex])
        }
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
