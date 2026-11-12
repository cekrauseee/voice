import Foundation
import VoiceCore

/// A meeting's connection to the server, which outlives the socket.
///
/// Audio goes out as it comes, with the time of the meeting it was recorded at. When the
/// socket drops, another is opened after a wait that grows with each failure, and the audio
/// the server has not confirmed is sent again, from where the server has each channel.
/// None of this is shown to the user.
@MainActor
final class MeetingLink {
  private let server: URL
  private let instructions: String
  private let log = Log("meeting")
  private var socket: URLSessionWebSocketTask?
  private var tails: [Channel: ReplayTail] = [.me: ReplayTail(), .others: ReplayTail()]
  private var failures = 0
  private var reconnection: Task<Void, Never>?
  private var deadline: Task<Void, Never>?
  private var isStopping = false
  private var isOver = false

  /// The id for the next segment, asked when a connection opens.
  var nextId: () -> Int = { 1 }
  var onMessage: (MeetingServerMessage) -> Void = { _ in }
  /// The connection was lost. Another is on its way.
  var onReconnecting: () -> Void = {}
  /// The meeting is over on the server, or the link gave up waiting for it to be.
  var onEnd: () -> Void = {}

  /// How long the server gets to say `done` after the stop, connected or not.
  private static let stopTimeout: Duration = .seconds(20)

  init(server: URL, instructions: String) {
    self.server = server
    self.instructions = instructions
  }

  func start() {
    connect()
  }

  /// Sends audio recorded at a time of the meeting. While disconnected it waits for the
  /// next connection.
  func send(_ channel: Channel, _ pcm: Data, at time: TimeInterval) {
    guard !isOver, !isStopping else { return }
    tails[channel]?.append(pcm, at: time, isConnected: socket != nil)
    socket?.send(.data(AudioFrame.make(channel, pcm))) { _ in }
  }

  /// The meeting is over. The server says `done` on this connection or the next.
  func stop() {
    guard !isOver, !isStopping else { return }
    isStopping = true
    if socket != nil { send(.stop) }
    deadline = Task { [weak self] in
      try? await Task.sleep(for: Self.stopTimeout)
      guard let self, !Task.isCancelled else { return }
      log.error("stop timed out", ["connected": socket != nil])
      end()
    }
  }

  /// The meeting is dropped: the connection closes now, and `onEnd` is not called.
  func cancel() {
    onEnd = {}
    end()
  }

  private func connect() {
    guard !isOver else { return }
    let socket = URLSession.shared.webSocketTask(
      with: server.appending(path: MeetingServerMessage.path))
    self.socket = socket
    socket.resume()

    var offsets: [Channel: TimeInterval] = [:]
    var replays: [(Channel, [Data])] = []
    for channel in Channel.allCases {
      let replay = tails[channel]?.replay ?? (offset: 0, chunks: [])
      offsets[channel] = replay.offset
      replays.append((channel, replay.chunks))
    }
    send(.start(instructions: instructions, firstId: nextId(), offsets: offsets))
    var replayed = 0
    for (channel, chunks) in replays {
      for pcm in chunks {
        socket.send(.data(AudioFrame.make(channel, pcm))) { _ in }
        replayed += pcm.count
      }
    }
    if isStopping { send(.stop) }
    log.info(
      "connected",
      [
        "attempt": failures + 1,
        "replayed_ms": replayed / Int(AudioFormat.sampleRate * 2 / 1000),
      ])
    Task { await receive(socket) }
  }

  private func receive(_ socket: URLSessionWebSocketTask) async {
    while !isOver, self.socket === socket {
      do {
        guard case .string(let json) = try await socket.receive(),
          let message = MeetingServerMessage(json: json)
        else { continue }
        handle(message)
      } catch {
        if self.socket === socket { lost(error) }
        return
      }
    }
  }

  private func handle(_ message: MeetingServerMessage) {
    switch message {
    case .ready:
      failures = 0
    case .segment(let segment):
      failures = 0
      tails[segment.channel]?.confirm(upTo: segment.end)
    case .done:
      onMessage(message)
      end()
      return
    case .error(let code):
      // The server closes after it. The next connection picks the meeting up.
      log.error("server failed", ["code": code])
    case .draft, .usage:
      break
    }
    onMessage(message)
  }

  /// The socket is gone. Another is opened after a wait.
  private func lost(_ error: Error) {
    guard !isOver else { return }
    socket?.cancel()
    socket = nil
    failures += 1
    let delay = Backoff.delay(afterFailures: failures)
    log.error(
      "connection lost",
      [
        "error": error.localizedDescription,
        "failures": failures,
        "retry_ms": Int(delay / .milliseconds(1)),
      ])
    onReconnecting()
    reconnection = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard let self, !Task.isCancelled else { return }
      connect()
    }
  }

  private func send(_ message: MeetingClientMessage) {
    socket?.send(.string(message.json)) { _ in }
  }

  private func end() {
    guard !isOver else { return }
    isOver = true
    reconnection?.cancel()
    deadline?.cancel()
    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    onEnd()
  }
}
