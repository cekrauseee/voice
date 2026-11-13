import AppKit

/// Pastes each dictation with its own clipboard and Enter preferences.
@MainActor
final class TextInserter {
  /// Marks the key events this app posts, so its own shortcuts ignore them.
  nonisolated static let eventMarker: Int64 = 0x566F_6963_65

  private struct Insertion {
    let text: String
    let keepOnClipboard: Bool
    let pressEnter: Bool
  }

  private var pending: [Insertion] = []
  private var isPasting = false

  func insert(_ text: String, keepOnClipboard: Bool = false, pressEnter: Bool = false) {
    guard !text.isEmpty else { return }
    pending.append(Insertion(text: text, keepOnClipboard: keepOnClipboard, pressEnter: pressEnter))
    guard !isPasting else { return }
    isPasting = true
    Task {
      while !pending.isEmpty {
        await paste(pending.removeFirst())
      }
      isPasting = false
    }
  }

  private func paste(_ insertion: Insertion) async {
    let pasteboard = NSPasteboard.general
    let saved = pasteboard.pasteboardItems?.map { item in
      item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { contents, type in
        contents[type] = item.data(forType: type)
      }
    }

    pasteboard.clearContents()
    pasteboard.setString(insertion.text, forType: .string)
    let changeCount = pasteboard.changeCount
    press(9, flags: .maskCommand)
    // Give the focused app time to read the clipboard before Enter or restoration.
    try? await Task.sleep(for: .milliseconds(150))
    if insertion.pressEnter { press(36) }

    // A newer copy by the user or another app takes precedence over restoration.
    guard !insertion.keepOnClipboard, pasteboard.changeCount == changeCount else { return }
    pasteboard.clearContents()
    pasteboard.writeObjects(
      (saved ?? []).map { contents in
        let item = NSPasteboardItem()
        for (type, data) in contents { item.setData(data, forType: type) }
        return item
      })
  }

  private func press(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .privateState)
    for keyDown in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
      event?.flags = flags
      event?.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
      event?.post(tap: .cghidEventTap)
    }
  }
}
