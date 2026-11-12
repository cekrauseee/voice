import Foundation
import VoiceCore

/// Runs the server on this Mac for the production app. It starts with the app and stops with it.
/// The app holds the server's standard input open: if the app ends without stopping the server,
/// as in a crash, the input closes and the server stops by itself.
@MainActor
final class ServerProcess {
  /// Why the server cannot run, for the user: a title and a sentence or two.
  struct Failure: Error {
    let title: String
    let detail: String
  }

  /// The server's records, one JSON object per line. The log starts over with each run.
  static let logFile = URL.libraryDirectory.appending(path: "Logs/\(AppInfo.identifier)/server.log")

  private let log = Log("server")
  private let process = Process()
  private let input = Pipe()
  private var isStopping = false
  private var onStop: (Failure) -> Void = { _ in }

  /// Starts the server. `onStop` is called if it stops by itself, with why.
  func start(environmentFile: String?, onStop: @escaping (Failure) -> Void) throws(Failure) {
    let files = FileManager.default
    guard let node = LocalServer.node(isExecutable: files.isExecutableFile) else {
      throw Failure(
        title: "Node.js is missing",
        detail: "Voice runs its server with Node.js. Install it with Homebrew: brew install node")
    }
    guard let environmentFile, files.fileExists(atPath: environmentFile) else {
      throw Failure(
        title: "The server has no settings",
        detail:
          "Run pnpm install-app in the Voice repository. It sets the app up with apps/server/.env."
      )
    }
    guard let script = Bundle.main.path(forResource: "server", ofType: "mjs") else {
      throw Failure(title: "The server is missing", detail: "Run pnpm install-app again.")
    }

    let output: FileHandle
    do {
      try files.createDirectory(
        at: Self.logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
      files.createFile(atPath: Self.logFile.path, contents: nil)
      output = try FileHandle(forWritingTo: Self.logFile)
    } catch {
      throw Failure(title: "The server could not start", detail: error.localizedDescription)
    }

    process.executableURL = URL(filePath: node)
    process.arguments = LocalServer.arguments(script: script, environmentFile: environmentFile)
    process.environment = ProcessInfo.processInfo.environment.merging(LocalServer.environment) {
      $1
    }
    process.standardInput = input
    process.standardOutput = output
    process.standardError = output
    self.onStop = onStop
    process.terminationHandler = { [weak self] process in
      let status = process.terminationStatus
      Task { @MainActor in self?.stopped(status: status) }
    }
    do {
      try process.run()
    } catch {
      throw Failure(title: "The server could not start", detail: error.localizedDescription)
    }
    log.info(
      "started",
      ["pid": process.processIdentifier, "port": LocalServer.port, "log": Self.logFile.path])
  }

  /// Stops the server, when the app quits.
  func stop() {
    guard process.isRunning else { return }
    isStopping = true
    process.terminate()
  }

  private func stopped(status: Int32) {
    guard !isStopping else { return }
    let records = (try? String(contentsOf: Self.logFile, encoding: .utf8)) ?? ""
    let failure = ServerFailure(log: records)
    log.error("stopped", ["status": status, "error": failure?.message ?? "none"])
    onStop(
      Failure(
        title: "The server stopped",
        detail: failure?.text ?? "Its log is in ~/Library/Logs/\(AppInfo.identifier)/server.log."))
  }
}
