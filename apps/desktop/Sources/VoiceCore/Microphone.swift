/// A microphone the user chose to dictate with, remembered by its identifier and its name.
///
/// Two microphones are the same when their identifiers are: a device keeps its identifier
/// when its name changes.
public struct Microphone: Codable, Hashable, Sendable {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  /// The choices of microphone: the system's, then each one connected. A chosen one that is
  /// not connected stays among them, so the choice is kept until it is changed. Until it is
  /// connected again the system's records instead.
  public static func options(chosen: Microphone?, connected: [Microphone]) -> [(
    value: Microphone?, title: String
  )] {
    var options: [(value: Microphone?, title: String)] = [(nil, "System default")]
    options += connected.map { ($0, $0.name) }
    if let chosen, !connected.contains(chosen) {
      options.append((chosen, "\(chosen.name) (not connected)"))
    }
    return options
  }
}
