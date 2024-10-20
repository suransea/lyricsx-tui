import Dispatch
import Foundation
import LyricsService
import MusicPlayer
import Observation
import Synchronization
import Termbox

@MainActor
func observing(
  tracking: @MainActor @escaping () -> Void,
  didChange: @MainActor @escaping () -> Void
) {
  didChange()
  withObservationTracking {
    tracking()
  } onChange: {
    Task { await observing(tracking: tracking, didChange: didChange) }
  }
}

private func terminalEvents(
  on queue: DispatchQueue = DispatchQueue(label: "TerminalEvents")
) -> some AsyncSequence<Event, Never> {
  AsyncStream { continuation in
    let active = Atomic(true)
    continuation.onTermination = { _ in active.store(false, ordering: .relaxed) }
    queue.async {
      while let event = Termbox.pollEvent(), active.load(ordering: .relaxed) {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private func lyrics(of track: MusicTrack) async -> [Lyrics] {
  let request = LyricsSearchRequest(
    searchTerm: .info(title: track.title ?? "", artist: track.artist ?? ""),
    duration: track.duration ?? 0
  )
  var lyrics = [Lyrics]()
  for await lyric in LyricsProviders.Group().lyrics(request: request) {
    lyrics.append(lyric)
  }
  return lyrics.sorted { $0.quality > $1.quality }
}

private func index(of offset: TimeInterval, of lines: [LyricsLine]) -> [LyricsLine].Index {
  lines.firstIndex { $0.position > offset } ?? lines.count
}

@MainActor
private func timedIndices(
  of lines: [LyricsLine],
  for player: some MusicPlayerProtocol,
  fixDelay: TimeInterval = 0
) -> some AsyncSequence<[LyricsLine].Index, Never> {
  AsyncStream { continuation in
    let task = Task {
      let nextIndex = index(of: player.playbackTime - fixDelay, of: lines)
      continuation.yield(nextIndex - 1)
      for index in nextIndex..<lines.count {
        let sleepSeconds = lines[index].position - (player.playbackTime - fixDelay)
        try await Task.sleep(for: .seconds(sleepSeconds))
        continuation.yield(index)
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
  }
}

@MainActor
func playLyrics(
  for player: some MusicPlayerProtocol,
  highlightStyle: Attributes,
  fixDelay: TimeInterval = 0
) async throws {
  try Termbox.initialize()
  defer { Termbox.shutdown() }

  let state = LyricsPanelState()
  state.highlightStyle = highlightStyle
  renderingLyricsPanel(for: state)

  var presentingLyrics: Task<Void, Never>?
  let presentLyrics = {
    presentingLyrics?.cancel()
    presentingLyrics = Task {
      if state.playbackState.isPlaying {
        for await index in timedIndices(of: state.lyricsLines, for: player, fixDelay: fixDelay) {
          state.highlightIndex = index
        }
      } else {
        state.highlightIndex = index(of: player.playbackTime - fixDelay, of: state.lyricsLines) - 1
      }
    }
  }

  var loadingLyrics: Task<Void, Never>?
  let loadLyrics = {
    loadingLyrics?.cancel()
    loadingLyrics = Task {
      guard let track = state.track else { return }
      state.avaliableLyrics = await lyrics(of: track)
      presentLyrics()
    }
  }

  observing {
    _ = player.currentTrack
  } didChange: {
    state.track = player.currentTrack
    state.lyricsIndex = 0
    state.avaliableLyrics = []
    loadLyrics()
  }

  observing {
    _ = player.playbackState
  } didChange: {
    state.playbackState = player.playbackState
    presentLyrics()
  }

  loop: for await event in terminalEvents() {
    switch event {
    case .character(modifier: .none, value: "q"):
      break loop
    case .character(modifier: .none, value: "r"):
      loadLyrics()
      break
    case .resize(let width, let height):
      state.width = width
      state.height = height
      break
    case .key(modifier: .none, value: .arrowUp):
      let previousIndex =
        state.lyricsIndex == 0 ? state.avaliableLyrics.count - 1 : state.lyricsIndex - 1
      state.lyricsIndex = previousIndex
      presentLyrics()
      break
    case .key(modifier: .none, value: .arrowDown):
      let nextIndex =
        state.lyricsIndex == state.avaliableLyrics.count - 1 ? 0 : state.lyricsIndex + 1
      state.lyricsIndex = nextIndex
      presentLyrics()
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
}
