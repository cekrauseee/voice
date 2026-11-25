import Foundation
import VoiceCore

/// One dictation on the server: audio goes out, text comes back.
@MainActor
final class DictationSession {
  /// How long the server has to answer once the session opens, before it counts as
  /// unreachable. The server on this Mac answers at once, or refuses at once.
  static let connectTimeout = Duration.seconds(5)

  private let socket: URLSessionWebSocketTask
  private let opening: ClientMessage
  private(set) var transcript = Transcript()
  /// What the dictation used on the server, once it has its text.
  private(set) var usage: Usage?

  private var isConnected = false
  private var hasStopped = false
  private var isOver = false
  private var connecting: Task<Void, Never>?

  /// The server is transcribing.
  var onReady: () -> Void = {}
  /// The transcript changed.
  var onChange: () -> Void = {}
  /// The session is over. Done, `transcript.typed` is the text to type, which may begin with
  /// a space that joins it to the text before the cursor. Failed, it is the draft heard.
  var onEnd: (SessionEnd) -> Void = { _ in }

  /// `context` is the text before the cursor in the field the text goes into, if known.
  /// `live` asks for the words to be transcribed while the speaker talks, for the pill to show.
  init(
    server: URL, instructions: String, translateTo: String, vocabulary: [String],
    context: String = "", live: Bool = false
  ) {
    socket = URLSession.shared.webSocketTask(with: server.appending(path: ServerMessage.path))
    opening = .start(
      instructions: instructions, translateTo: translateTo, vocabulary: vocabulary,
      context: context, live: live)
  }

  func start() {
    socket.resume()
    send(opening)
    // The pong says the server is there, live or not, before it has anything to say.
    socket.sendPing { [weak self] error in
      guard error == nil else { return }
      Task { @MainActor in self?.isConnected = true }
    }
    connecting = Task { [weak self] in
      try? await Task.sleep(for: Self.connectTimeout)
      guard !Task.isCancelled, let self, !isConnected else { return }
      end(.disconnected)
    }
    Task { await receive() }
  }

  func send(_ pcm: Data) {
    guard !isOver else { return }
    socket.send(.data(pcm)) { _ in }
  }

  /// Sends a whole recording as fast as the server takes it, not at the pace it was spoken,
  /// and says the speaker is done.
  func send(recording pcm: Data) {
    let chunk = AudioFormat.chunkSamples * MemoryLayout<Int16>.size
    for offset in stride(from: 0, to: pcm.count, by: chunk) {
      send(
        pcm.subdata(
          in: (pcm.startIndex + offset)..<min(pcm.startIndex + offset + chunk, pcm.endIndex)))
    }
    stop()
  }

  /// Tells the server the speaker is done. The text follows.
  func stop() {
    hasStopped = true
    send(.stop)
  }

  /// Drops the dictation. Nothing is typed.
  func cancel() {
    isOver = true
    connecting?.cancel()
    socket.cancel()
  }

  private func send(_ message: ClientMessage) {
    guard !isOver else { return }
    socket.send(.string(message.json)) { _ in }
  }

  private func receive() async {
    while !isOver {
      do {
        guard case .string(let json) = try await socket.receive(),
          let message = ServerMessage(json: json)
        else { continue }
        isConnected = true
        handle(message)
      } catch {
        end(.disconnected)
      }
    }
  }

  private func handle(_ message: ServerMessage) {
    switch message {
    case .ready:
      onReady()
    case .delta:
      transcript.apply(message)
      onChange()
    case .done(_, let usage):
      self.usage = usage
      transcript.apply(message)
      onChange()
      end(.done(transcript.typed))
    case .error(let code):
      end(.failed(code: code, afterStop: hasStopped))
    }
  }

  private func end(_ end: SessionEnd) {
    guard !isOver else { return }
    isOver = true
    connecting?.cancel()
    socket.cancel(with: .normalClosure, reason: nil)
    onEnd(end)
  }
}
