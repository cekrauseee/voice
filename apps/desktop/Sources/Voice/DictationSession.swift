import Foundation
import VoiceCore

/// One dictation on the server: audio goes out, text comes back.
@MainActor
final class DictationSession {
  private let socket: URLSessionWebSocketTask
  private let instructions: String
  private(set) var transcript = Transcript()
  /// The audio that was sent: 16-bit mono PCM at 24 kHz.
  private(set) var recording = Data()
  /// What the dictation used on the server, once it has its text.
  private(set) var usage: Usage?

  /// How long the recording is, in seconds.
  var recorded: TimeInterval {
    Double(recording.count / MemoryLayout<Int16>.size) / AudioFormat.sampleRate
  }
  private var isReady = false
  private var isOver = false

  /// The server is transcribing.
  var onReady: () -> Void = {}
  /// The transcript changed.
  var onChange: () -> Void = {}
  /// The dictation has its text, which is empty when it failed before any word came back.
  var onText: (String, DictationError?) -> Void = { _, _ in }
  /// The dictation is over, with the reason when it failed.
  var onEnd: (DictationError?) -> Void = { _ in }

  init(server: URL, instructions: String) {
    socket = URLSession.shared.webSocketTask(with: server.appending(path: ServerMessage.path))
    self.instructions = instructions
  }

  func start() {
    socket.resume()
    send(.start(instructions: instructions))
    Task { await receive() }
  }

  func send(_ pcm: Data) {
    recording.append(pcm)
    socket.send(.data(pcm)) { _ in }
  }

  /// Tells the server the speaker is done. The text follows.
  func stop() {
    send(.stop)
  }

  /// Drops the dictation. Nothing is typed.
  func cancel() {
    isOver = true
    socket.cancel()
  }

  private func send(_ message: ClientMessage) {
    socket.send(.string(message.json)) { _ in }
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
    case .delta:
      transcript.apply(message)
      onChange()
    case .done(_, let usage):
      self.usage = usage
      transcript.apply(message)
      onChange()
      end(nil)
    case .error:
      end(.transcriptionFailed)
    }
  }

  private func end(_ error: DictationError?) {
    guard !isOver else { return }
    isOver = true
    socket.cancel(with: .normalClosure, reason: nil)
    // Refined when the dictation finished, as heard when it failed: what was said is not lost.
    onText(transcript.text.trimmingCharacters(in: .whitespacesAndNewlines), error)
    onEnd(error)
  }
}
