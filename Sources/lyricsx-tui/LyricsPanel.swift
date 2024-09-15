import Foundation
import LyricsCore
import MusicPlayer
import Termbox

@Observable
class LyricsPanelState {
  var padding: Int32 = 2
  var width: Int32 = Termbox.width
  var height: Int32 = Termbox.height
  var playbackState: PlaybackState = .stopped
  var track: MusicTrack?
  var avaliableLyrics: [Lyrics] = []
  var lyricsIndex: Int = 0
  var highlightIndex: Int = 0
  var highlightStyle: Attributes = [.cyan, .bold]

  var title: String {
    track?.title ?? "-"
  }
  var artist: String? {
    track?.artist
  }
  var album: String? {
    track?.album
  }

  var lyrics: Lyrics? {
    avaliableLyrics.indices.contains(lyricsIndex) ? avaliableLyrics[lyricsIndex] : nil
  }

  var lyricsLines: [LyricsLine] {
    lyrics?.lines ?? []
  }

  var lyricsSource: String {
    lyrics.map { $0.metadata.service?.rawValue ?? "Unknown" } ?? "-"
  }

  var topBarContent: String {
    var bar = "Title: \(title)"
    if let artist = artist {
      bar += " | Artist: \(artist)"
    }
    if let album = album {
      bar += " | Album: \(album)"
    }
    return bar
  }

  var bottomBarContent: String {
    let status =
      switch playbackState {
      case .playing: "Playing"
      case .paused: "Paused"
      case .stopped: "Stopped"
      default: "Stopped"
      }
    let lyricsIndicator = lyrics.map { _ in "(\(lyricsIndex + 1)/\(avaliableLyrics.count))" } ?? ""
    return "State: \(status) | Lyric Source: \(lyricsSource) \(lyricsIndicator)"
  }
}

@MainActor
func renderLyricsPanel(for state: LyricsPanelState) {
  observing {
    clearTopBar()
    renderAt(
      x: state.padding, y: 0, text: state.topBarContent, foreground: .black, background: .white)
    Termbox.present()
  } tracking: {
    _ = state.topBarContent
    _ = state.padding
    _ = state.width
  }
  observing {
    clearBottomBar()
    renderAt(
      x: state.padding, y: Termbox.height - 1, text: state.bottomBarContent,
      foreground: .black, background: .white)
    Termbox.present()
  } tracking: {
    _ = state.bottomBarContent
    _ = state.padding
    _ = (state.height, state.width)
  }
  observing {
    clearLyricsArea()
    renderLyricsArea(for: state)
    Termbox.present()
  } tracking: {
    _ = state.lyricsLines
    _ = state.highlightIndex
    _ = state.highlightStyle
    _ = state.padding
    _ = (state.height, state.width)
  }
}

@MainActor
private func observing(_ block: @escaping () -> Void, tracking: @escaping () -> Void) {
  block()
  withObservationTracking {
    tracking()
  } onChange: {
    Task { await observing(block, tracking: tracking) }
  }
}

private func renderAt(
  x: Int32, y: Int32, text: String,
  foreground: Attributes = .default,
  background: Attributes = .default
) {
  for (c, xi) in zip(text.unicodeScalars, x..<Termbox.width) {
    Termbox.put(x: xi, y: y, character: c, foreground: foreground, background: background)
  }
}

private func clearTopBar() {
  for i in 0..<Termbox.width {
    Termbox.put(x: i, y: 0, character: " ", background: .white)
  }
}

private func clearBottomBar() {
  for i in 0..<Termbox.width {
    Termbox.put(x: i, y: Termbox.height - 1, character: " ", background: .white)
  }
}

private func clearLyricsArea() {
  for i in 0..<Termbox.width {
    for j in 1..<Termbox.height - 1 {
      Termbox.put(x: i, y: j, character: " ")
    }
  }
}

private func renderLyricsArea(for state: LyricsPanelState) {
  let middle = Termbox.height / 2
  let lines = state.lyricsLines
  let index = state.highlightIndex
  let padding = state.padding
  if lines.indices.contains(state.highlightIndex) {
    renderAt(x: padding, y: middle, text: lines[index].content, foreground: state.highlightStyle)
  }
  for (line, pos) in zip(lines.prefix(max(index, 0)).reversed(), (padding..<middle).reversed()) {
    renderAt(x: padding, y: pos, text: line.content)
  }
  for (line, pos) in zip(lines.dropFirst(index + 1), middle + 1..<Termbox.height - padding) {
    renderAt(x: padding, y: pos, text: line.content)
  }
}
