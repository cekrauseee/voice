import Foundation
import Testing

@testable import VoiceCore

@Suite struct LocalServerTests {
  @Test func usesTheFirstNodeFound() {
    #expect(LocalServer.node { _ in true } == "/opt/homebrew/bin/node")
    #expect(LocalServer.node { $0 == "/usr/local/bin/node" } == "/usr/local/bin/node")
    #expect(LocalServer.node { _ in false } == nil)
  }

  @Test func runsTheScriptWithTheServerSettings() {
    #expect(
      LocalServer.arguments(script: "/Voice.app/server.mjs", environmentFile: "/voice/.env")
        == ["--env-file=/voice/.env", "/Voice.app/server.mjs"])
  }

  @Test func listensOnTheLoopbackAtItsOwnPort() {
    #expect(LocalServer.environment["HOST"] == "127.0.0.1")
    #expect(LocalServer.environment["PORT"] == "8788")
    #expect(LocalServer.url.port == 8788)
    #expect(LocalServer.environment["STOP_WITH_PARENT"] == "1")
  }
}

@Suite struct ServerFailureTests {
  @Test func isTheLastErrorLogged() {
    let log = """
      {"level":"info","scope":"server","message":"listening","url":"ws://127.0.0.1:8788"}
      {"level":"error","scope":"dictation","message":"transcription failed","dictation":1}
      {"level":"error","scope":"server","message":"port is in use","port":8788,"hint":"set PORT"}
      {"level":"info","scope":"server","message":"stopping","signal":"SIGTERM"}

      """
    #expect(ServerFailure(log: log) == ServerFailure(message: "port is in use", hint: "set PORT"))
  }

  @Test func skipsWhatIsNotARecord() {
    let log = """
      node:internal/modules/run_main:123
      SyntaxError: Unexpected token
      {"level":"error","scope":"server","message":"OPENAI_API_KEY is not set"}
      """
    #expect(ServerFailure(log: log) == ServerFailure(message: "OPENAI_API_KEY is not set"))
    #expect(ServerFailure(log: "SyntaxError: Unexpected token") == nil)
  }

  @Test func readsAsSentences() {
    #expect(
      ServerFailure(message: "OPENAI_API_KEY is not set", hint: "add your key to apps/server/.env")
        .text == "OPENAI_API_KEY is not set. Add your key to apps/server/.env.")
    #expect(ServerFailure(message: "port is in use").text == "Port is in use.")
  }
}
