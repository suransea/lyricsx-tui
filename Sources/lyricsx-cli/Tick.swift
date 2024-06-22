import CXShim
import Foundation
import LyricsService
import MusicPlayer

func tick() {
  guard let player = CurrentPlayer() else {
    fatalError("Unable to connect to the music player.")
  }

  var cancelBag = [AnyCancellable]()
  var currentIndex = -1

  player.currentTrackWillChange
    .prepend(nil)
    .handleEvents(receiveOutput: { track in
      if let track = track {
        print("\nTrack:\n")
        print("Title: \(track.title ?? "")")
        print("Artist: \(track.artist ?? "")")
        print("Album: \(track.album ?? "")\n")
      }
    })
    .flatMap { track in
      track.map {
        lyrics(of: $0).map(\.first).prepend(nil).eraseToAnyPublisher()
      } ?? Just(nil).eraseToAnyPublisher()
    }
    .handleEvents(receiveOutput: { lyrics in
      if let lyrics = lyrics {
        print("\nLyric Source: \(lyrics.metadata.service?.rawValue ?? "Unknown")\n")
      } else {
        currentIndex = -1
      }
    })
    .combineLatest(player.playbackStateWillChange.prepend(.stopped))
    .map { lyrics, state in
      if let lyrics = lyrics {
        let index = index(of: state.time, of: lyrics.lines)
        let dropCount = index < currentIndex ? 0 : 1 + currentIndex
        currentIndex = index
        lyrics.lines.prefix(index).dropFirst(dropCount).forEach { print($0.content) }
        if state.isPlaying {
          return timedIndices(of: lyrics.lines, on: .main, with: player)
            .map { (lyrics.lines[$0], $0) }.eraseToAnyPublisher()
        }
      }
      return Empty().eraseToAnyPublisher()
    }
    .switchToLatest()
    .receive(on: DispatchQueue.main.cx)
    .sink { line, index in
      currentIndex = index
      print(line.content)
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
