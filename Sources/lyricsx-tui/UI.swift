import Foundation
import LyricsCore
import MusicPlayer
import Termbox

private let NO_CONTENT = "-"
private let UNKNOWN = "Unknown"
private let SPACE: Int32 = 2

private func printAt(
  x: Int32, y: Int32, text: String, foreground: Attributes = .default,
  background: Attributes = .default
) {
  for (c, xi) in zip(text.unicodeScalars, x..<Termbox.width) {
    Termbox.put(x: xi, y: y, character: c, foreground: foreground, background: background)
  }
}

func clearTopBar() {
  for i in 0..<Termbox.width {
    Termbox.put(x: i, y: 0, character: " ", background: .white)
  }
}

func clearBottomBar() {
  for i in 0..<Termbox.width {
    Termbox.put(x: i, y: Termbox.height - 1, character: " ", background: .white)
  }
}

func clearLyricArea() {
  for i in 0..<Termbox.width {
    for j in 1..<Termbox.height - 1 {
      Termbox.put(x: i, y: j, character: " ")
    }
  }
}

func updateTopBar(track: MusicTrack?) {
  if let track = track {
    updateTopBar(title: track.title ?? UNKNOWN, artist: track.artist, album: track.album)
  } else {
    updateTopBar(title: NO_CONTENT, artist: NO_CONTENT, album: NO_CONTENT)
  }
}

func updateTopBar(title: String, artist: String?, album: String?) {
  clearTopBar()
  var bar = "Title: \(title)"
  if let artist = artist { bar += " | Artist: \(artist)" }
  if let album = album { bar += " | Album: \(album)" }
  printAt(x: SPACE, y: 0, text: bar, foreground: .black, background: .white)
}

func updateBottomBar(state: PlaybackState, lyric: Lyrics?, index: Int, count: Int) {
  let source: String
  if let lyric = lyric {
    source = "\(lyric.metadata.service?.rawValue ?? UNKNOWN) (\(index + 1)/\(count))"
  } else {
    source = NO_CONTENT
  }
  updateBottomBar(state: state, source: source)
}

func updateBottomBar(state: PlaybackState, source: String) {
  clearBottomBar()
  let status: String = {
    switch state {
    case .playing: return "Playing"
    case .paused: return "Paused"
    case .stopped: return "Stopped"
    default: return "Stopped"
    }
  }()
  let bar = "State: \(status) | Lyric Source: \(source)"
  printAt(x: SPACE, y: Termbox.height - 1, text: bar, foreground: .black, background: .white)
}

func updateLyricArea(lines: [LyricsLine], index: Int, foreground: Attributes) {
  clearLyricArea()
  let middle = Termbox.height / 2
  if lines.indices.contains(index) {
    printAt(x: SPACE, y: middle, text: lines[index].content, foreground: foreground)
  }
  for (line, pos) in zip(lines.prefix(max(index, 0)).reversed(), (SPACE..<middle).reversed()) {
    printAt(x: SPACE, y: pos, text: line.content)
  }
  for (line, pos) in zip(lines.dropFirst(index + 1), middle + 1..<Termbox.height - SPACE) {
    printAt(x: SPACE, y: pos, text: line.content)
  }
}
