/// Virtual key codes of the keys the app refers to by name.
public enum KeyCode {
  public static let space: UInt16 = 49
  public static let escape: UInt16 = 53
}

/// The modifiers held with a key, without telling left from right.
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let control = Modifiers(rawValue: 1 << 0)
  public static let option = Modifiers(rawValue: 1 << 1)
  public static let shift = Modifiers(rawValue: 1 << 2)
  public static let command = Modifiers(rawValue: 1 << 3)

  /// Reads the modifiers from the raw flags of a keyboard event.
  public init(eventFlags: UInt64) {
    var modifiers: Modifiers = []
    if eventFlags & 0x4_0000 != 0 { modifiers.insert(.control) }
    if eventFlags & 0x8_0000 != 0 { modifiers.insert(.option) }
    if eventFlags & 0x2_0000 != 0 { modifiers.insert(.shift) }
    if eventFlags & 0x10_0000 != 0 { modifiers.insert(.command) }
    self = modifiers
  }

  var symbols: [String] {
    var symbols: [String] = []
    if contains(.control) { symbols.append("⌃") }
    if contains(.option) { symbols.append("⌥") }
    if contains(.shift) { symbols.append("⇧") }
    if contains(.command) { symbols.append("⌘") }
    return symbols
  }
}

/// A physical modifier key, identified by its virtual key code.
public enum ModifierKey: UInt16, CaseIterable, Sendable {
  case rightCommand = 54
  case leftCommand = 55
  case leftShift = 56
  case leftOption = 58
  case leftControl = 59
  case rightShift = 60
  case rightOption = 61
  case rightControl = 62
  case function = 63

  /// The modifier this key contributes. The fn key contributes none.
  public var modifier: Modifiers {
    switch self {
    case .leftCommand, .rightCommand: .command
    case .leftShift, .rightShift: .shift
    case .leftOption, .rightOption: .option
    case .leftControl, .rightControl: .control
    case .function: []
    }
  }

  /// Whether this key is down, according to the raw flags of a keyboard event.
  public func isDown(eventFlags: UInt64) -> Bool {
    let mask: UInt64 =
      switch self {
      case .leftControl: 0x1
      case .leftShift: 0x2
      case .rightShift: 0x4
      case .leftCommand: 0x8
      case .rightCommand: 0x10
      case .leftOption: 0x20
      case .rightOption: 0x40
      case .rightControl: 0x2000
      case .function: 0x80_0000
      }
    return eventFlags & mask != 0
  }

  var name: String {
    switch self {
    case .leftCommand: "Left ⌘"
    case .rightCommand: "Right ⌘"
    case .leftShift: "Left ⇧"
    case .rightShift: "Right ⇧"
    case .leftOption: "Left ⌥"
    case .rightOption: "Right ⌥"
    case .leftControl: "Left ⌃"
    case .rightControl: "Right ⌃"
    case .function: "fn"
    }
  }
}

/// A keyboard shortcut: a key with modifiers, or a single modifier key on its own.
public struct Shortcut: Codable, Hashable, Sendable {
  public var keyCode: UInt16
  public var modifiers: Modifiers

  public init(keyCode: UInt16, modifiers: Modifiers = []) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  public static let defaultPushToTalk = Shortcut(keyCode: ModifierKey.rightOption.rawValue)
  public static let defaultToggle = Shortcut(keyCode: KeyCode.space, modifiers: .option)

  /// The modifier key this shortcut consists of, when it has no other key.
  public var modifierKey: ModifierKey? {
    ModifierKey(rawValue: keyCode)
  }

  /// The labels of the keys to press, in order.
  public var keyCaps: [String] {
    if let modifierKey { return [modifierKey.name] }
    return modifiers.symbols + [Self.keyNames[keyCode] ?? "Key \(keyCode)"]
  }

  /// Key names on a US keyboard.
  private static let keyNames: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
    12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
    22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
    32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K",
    41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
    50: "`", 51: "Delete", 53: "esc", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
    101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12",
    113: "F15", 114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4",
    119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
  ]

  /// Function keys can be shortcuts without a modifier, since they type nothing.
  static func isFunctionKey(_ keyCode: UInt16) -> Bool {
    keyNames[keyCode]?.wholeMatch(of: /F\d+/) != nil
  }
}

/// A keyboard event, reduced to what shortcuts depend on.
public enum KeyEvent: Equatable, Sendable {
  case keyDown(keyCode: UInt16, modifiers: Modifiers, isRepeat: Bool)
  case keyUp(keyCode: UInt16)
  /// A modifier key went down or up. `modifiers` are the ones held after the change.
  case modifierChanged(key: ModifierKey, isDown: Bool, modifiers: Modifiers)
}
