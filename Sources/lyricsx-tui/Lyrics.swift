import Combine
import Dispatch
import Foundation
import LyricsService
import MusicPlayer
import Termbox

func lyrics(of track: MusicTrack) -> some Publisher<[Lyrics], Never> {
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

func index(of offset: TimeInterval, of lines: [LyricsLine]) -> Int {
  lines.firstIndex { $0.position > offset } ?? lines.count
}

func timedIndices(
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
