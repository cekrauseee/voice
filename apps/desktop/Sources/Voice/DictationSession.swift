import Foundation
import VoiceCore

/// One dictation on the server: audio goes out, text comes back.
@MainActor
final class DictationSession {
  private let socket: URLSessionWebSocketTask
  private(set) var transcript = Transcript()
  private var isReady = false
  private var isOver = false

  /// The server is transcribing.
  var onReady: () -> Void = {}
  /// The transcript changed.
  var onChange: () -> Void = {}
  /// Text is ready to be typed into the focused field.
  var onText: (String) -> Void = { _ in }
  /// The dictation is over, with the reason when it failed.
  var onEnd: (DictationError?) -> Void = { _ in }

  init(server: URL) {
    socket = URLSession.shared.webSocketTask(with: server.appending(path: ServerMessage.path))
  }

  func start() {
    socket.resume()
    Task { await receive() }
  }

  func send(_ pcm: Data) {
    socket.send(.data(pcm)) { _ in }
  }

  /// Tells the server the speaker is done. The remaining text still arrives.
  func stop() {
    socket.send(.string(ServerMessage.stop)) { _ in }
  }

  /// Drops the dictation, and the text that has not arrived.
  func cancel() {
    isOver = true
    socket.cancel()
  }

  private func receive() async {
    while !isOver {
      do {
        guard case .string(let json) = try await socket.receive(),
          let message = ServerMessage(json: json)
        else { continue }
        handle(message)
      } catch {
        end(isReady ? .transcriptionFailed : .serverUnreachable)
      }
    }
  }

  private func handle(_ message: ServerMessage) {
    switch message {
    case .ready:
      isReady = true
      onReady()
    case .done:
      end(nil)
    case .error:
      end(.transcriptionFailed)
    case .delta, .final, .refined:
      if let text = transcript.apply(message) { onText(text) }
      onChange()
    }
  }

  private func end(_ error: DictationError?) {
    guard !isOver else { return }
    isOver = true
    socket.cancel(with: .normalClosure, reason: nil)
    onEnd(error)
  }
}
