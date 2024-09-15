import Combine
import Dispatch
import Foundation
import LyricsService
import MusicPlayer
import Termbox

private func terminalEvents(
  on queue: DispatchQueue = DispatchQueue(label: "TerminalEvents")
) -> some Publisher<Event, Never> {
  let publisher = PassthroughSubject<Event, Never>()
  var active = true
  func publish() {
    if let event = Termbox.pollEvent(), active {
      publisher.send(event)
    }
    if active { queue.async { publish() } }
  }
  return publisher.handleEvents(
    receiveSubscription: { _ in queue.async { publish() } },
    receiveCancel: { active = false })
}

private func lyrics(of track: MusicTrack) -> some Publisher<[Lyrics], Never> {
  LyricsProviders.Group()
    .lyricsPublisher(
      request: LyricsSearchRequest(
        searchTerm: .info(title: track.title ?? "", artist: track.artist ?? ""),
        duration: track.duration ?? 0)
    )
    .collect()
    .map { $0.sorted { $0.quality > $1.quality } }
    .ignoreError()
}

private func index(of offset: TimeInterval, of lines: [LyricsLine]) -> Int {
  lines.firstIndex { $0.position > offset } ?? lines.count
}

private func timedIndices(
  of lines: [LyricsLine], on queue: DispatchQueue,
  for player: MusicPlayerProtocol,
  fixDelay: TimeInterval = 0
) -> some Publisher<Array<LyricsLine>.Index, Never> {
  let publisher = PassthroughSubject<Int, Never>()
  var canceled = false
  func publish(next index: Int) {
    if canceled { return }
    if index >= lines.count {
      publisher.send(completion: .finished)
      return
    }
    queue.asyncAfter(
      deadline: .now() + (lines[index].position - (player.playbackTime - fixDelay))
    ) {
      if canceled { return }
      publisher.send(index)
      publish(next: index + 1)
    }
  }
  return publisher.handleEvents(
    receiveSubscription: { _ in
      queue.async {
        let nextIndex = index(of: player.playbackTime - fixDelay, of: lines)
        publisher.send(nextIndex - 1)
        publish(next: nextIndex)
      }
    }, receiveCancel: { canceled = true })
}

func playLyrics(
  for player: some MusicPlayerProtocol,
  highlightStyle: Attributes,
  fixDelay: TimeInterval = 0
) {
  do { try Termbox.initialize() } catch {
    fatalError("\(error)")
  }
  defer { Termbox.shutdown() }

  var cancelBag = [AnyCancellable]()
  let playingLyrics = CurrentValueSubject<([Lyrics], [Lyrics].Index), Never>(([], 0))

  let state = LyricsPanelState()
  state.highlightStyle = highlightStyle
  Task { await renderLyricsPanel(for: state) }

  playingLyrics.combineLatest(player.playbackStateWillChange.prepend(player.playbackState))
    .map { lyrics, playbackState in
      let (avaliableLyrics, lyricsIndex) = lyrics
      state.avaliableLyrics = avaliableLyrics
      state.lyricsIndex = lyricsIndex
      state.playbackState = playbackState
      if playbackState.isPlaying {
        return timedIndices(of: state.lyricsLines, on: .main, for: player, fixDelay: fixDelay)
          .eraseToAnyPublisher()
      }
      return Just(index(of: player.playbackTime - fixDelay, of: state.lyricsLines) - 1)
        .eraseToAnyPublisher()
    }
    .switchToLatest()
    .sink { hightlightIndex in
      state.hightlightIndex = hightlightIndex
    }
    .store(in: &cancelBag)

  player.currentTrackWillChange.prepend(player.currentTrack)
    .handleEvents(receiveOutput: { track in
      state.track = track
      playingLyrics.send(([], 0))
    })
    .flatMap { track in
      track.map { lyrics(of: $0).eraseToAnyPublisher() } ?? Just([]).eraseToAnyPublisher()
    }
    .sink { lyrics in
      playingLyrics.send((lyrics, 0))
    }
    .store(in: &cancelBag)

  let reloadLyrics = {
    guard let track = player.currentTrack else { return }
    lyrics(of: track)
      .sink { lyrics in
        playingLyrics.send((lyrics, 0))
      }
      .store(in: &cancelBag)
  }

  terminalEvents()
    .sink { event in
      switch event {
      case .character(modifier: .none, value: "r"):
        reloadLyrics()
        break
      case .resize(let width, let height):
        state.width = width
        state.height = height
        break
      case .key(modifier: .none, value: .arrowUp):
        let previousIndex =
          state.lyricsIndex == 0 ? state.avaliableLyrics.count - 1 : state.lyricsIndex - 1
        playingLyrics.send((state.avaliableLyrics, previousIndex))
        break
      case .key(modifier: .none, value: .arrowDown):
        let nextIndex =
          state.lyricsIndex == state.avaliableLyrics.count - 1 ? 0 : state.lyricsIndex + 1
        playingLyrics.send((state.avaliableLyrics, nextIndex))
        break
      case .character(modifier: .none, value: "q"):
        cancelBag = []
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
}
