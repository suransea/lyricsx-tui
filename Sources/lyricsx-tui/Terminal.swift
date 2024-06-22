import Combine
import Dispatch
import Foundation
import Termbox

func terminalEvents(
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
