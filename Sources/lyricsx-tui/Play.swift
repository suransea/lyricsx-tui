import Combine
import Dispatch
import Foundation
import LyricsService
import MusicPlayer
import Termbox

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
  with player: MusicPlayerProtocol,
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
      queue.async { publish(next: index(of: player.playbackTime - fixDelay, of: lines)) }
    }, receiveCancel: { canceled = true })
}

func playLyrics(
  for player: MusicPlayerProtocol,
  on queue: DispatchQueue,
  foreground: Attributes, fixDelay: TimeInterval = 0,
  terminalEvents: some Publisher<Event, Never>
) -> () -> Void {
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
            of: lyrics.lines, on: queue, with: player, fixDelay: fixDelay
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
    .receive(on: queue)
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

  let changeLyrics = { (index: Int) in
    if fetchedLyrics.isEmpty { return }
    lyricsIndex = index
    if lyricsIndex < 0 {
      lyricsIndex = fetchedLyrics.count - 1
    }
    if lyricsIndex >= fetchedLyrics.count {
      lyricsIndex = 0
    }
    playingLyrics.send(fetchedLyrics[lyricsIndex])
  }

  terminalEvents
    .receive(on: queue)
    .sink { event in
      switch event {
      case .character(modifier: .none, value: "r"):
        reloadLyrics()
        break
      case .resize(width: _, height: _):
        forceUpdate()
        break
      case .key(modifier: .none, value: .arrowUp):
        changeLyrics(lyricsIndex - 1)
        break
      case .key(modifier: .none, value: .arrowDown):
        changeLyrics(lyricsIndex + 1)
        break
      default:
        break
      }
    }
    .store(in: &cancelBag)

  return { cancelBag = [] }
}
