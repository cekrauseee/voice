import Foundation
import VoiceCore

/// One turn of the profile conversation on the server: what the user says goes out, the
/// agent's answer comes back.
@MainActor
final class ProfileTurnSession {
  private let socket: URLSessionWebSocketTask
  /// The message that opens the turn, with the conversation so far.
  private let opening: String
  private var isConnected = false
  private var isOver = false
  private var connecting: Task<Void, Never>?

  /// A message of the turn, as it comes.
  var onMessage: (ProfileTurnMessage) -> Void = { _ in }
  /// The turn is over, with the reason when the connection failed. A failure the server
  /// reports comes as a message instead.
  var onEnd: (DictationError?) -> Void = { _ in }

  init(server: URL, start: String) {
    socket = URLSession.shared.webSocketTask(
      with: server.appending(path: ProfileTurnMessage.path))
    opening = start
  }

  func start() {
    socket.resume()
    socket.send(.string(opening)) { _ in }
    // As for a dictation: the pong says the server is there before it has anything to say.
    socket.sendPing { [weak self] error in
      guard error == nil else { return }
      Task { @MainActor in self?.isConnected = true }
    }
    connecting = Task { [weak self] in
      try? await Task.sleep(for: DictationSession.connectTimeout)
      guard !Task.isCancelled, let self, !isConnected else { return }
      end(.offline(saved: false))
    }
    Task { await receive() }
  }

  func send(_ pcm: Data) {
    guard !isOver else { return }
    socket.send(.data(pcm)) { _ in }
  }

  func stop() {
    socket.send(.string(#"{"type":"stop"}"#)) { _ in }
  }

  func cancel() {
    isOver = true
    connecting?.cancel()
    socket.cancel()
  }

  private func receive() async {
    while !isOver {
      do {
        guard case .string(let json) = try await socket.receive(),
          let message = ProfileTurnMessage(json: json)
        else { continue }
        isConnected = true
        handle(message)
      } catch {
        end(.offline(saved: false))
      }
    }
  }

  private func handle(_ message: ProfileTurnMessage) {
    onMessage(message)
    switch message {
    case .done: end(nil)
    // The conversation has the reason.
    case .error: end(nil)
    default: break
    }
  }

  private func end(_ error: DictationError?) {
    guard !isOver else { return }
    isOver = true
    connecting?.cancel()
    socket.cancel(with: .normalClosure, reason: nil)
    onEnd(error)
  }
}
