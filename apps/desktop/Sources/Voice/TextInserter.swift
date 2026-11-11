import AppKit

/// Types text into the focused field by pasting it, then puts the clipboard back.
@MainActor
final class TextInserter {
  /// Marks the key events this app posts, so its own shortcuts ignore them.
  nonisolated static let eventMarker: Int64 = 0x566F_6963_65

  private var pending = ""
  private var isPasting = false

  func insert(_ text: String) {
    pending += text
    guard !isPasting else { return }
    isPasting = true
    Task {
      await paste()
      isPasting = false
    }
  }

  private func paste() async {
    let pasteboard = NSPasteboard.general
    let saved = pasteboard.pasteboardItems?.map { item in
      item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { contents, type in
        contents[type] = item.data(forType: type)
      }
    }

    while !pending.isEmpty {
      pasteboard.clearContents()
      pasteboard.setString(pending, forType: .string)
      pending = ""
      pressCommandV()
      // Give the focused app time to read the clipboard before it changes again.
      try? await Task.sleep(for: .milliseconds(150))
    }

    pasteboard.clearContents()
    pasteboard.writeObjects(
      (saved ?? []).map { contents in
        let item = NSPasteboardItem()
        for (type, data) in contents { item.setData(data, forType: type) }
        return item
      })
  }

  private func pressCommandV() {
    let source = CGEventSource(stateID: .privateState)
    for keyDown in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: keyDown)
      event?.flags = .maskCommand
      event?.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
      event?.post(tap: .cghidEventTap)
    }
  }
}
