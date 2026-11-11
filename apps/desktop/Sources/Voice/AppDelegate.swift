import AVFoundation
import AppKit
import OSLog
import VoiceCore

private let logger = Logger(subsystem: "eu.cekrause.voice", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let settings = Settings()
  private lazy var controller = DictationController(settings: settings)
  private lazy var hotkeys = HotkeyTap(settings: settings, controller: controller)
  private lazy var pill = PillPanel(controller: controller, settings: settings)
  private lazy var settingsWindow = SettingsWindow(settings: settings)
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = mainMenu()
    statusItem.button?.image = NSImage(
      systemSymbolName: "waveform", accessibilityDescription: "Voice")
    statusItem.menu = NSMenu()
    statusItem.menu?.delegate = self

    track { [settings] in
      settings.theme
    } onChange: { theme in
      NSApp.appearance =
        switch theme {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
    pill.start()

    if !Permissions.isAccessibilityGranted {
      logger.info("Waiting for Accessibility access")
      Permissions.promptForAccessibility()
    }
    startHotkeys()
  }

  /// The shortcuts need Accessibility access, so this keeps trying until it is granted.
  private func startHotkeys() {
    if hotkeys.start() {
      logger.info("Shortcuts ready")
    } else {
      Task {
        try? await Task.sleep(for: .seconds(1))
        startHotkeys()
      }
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    if !Permissions.isAccessibilityGranted {
      menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
    }
    if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
      menu.addItem(item("Grant Microphone Access…", #selector(openMicrophoneSettings)))
    }
    if menu.numberOfItems > 0 { menu.addItem(.separator()) }
    menu.addItem(item("Settings…", #selector(openSettings), key: ","))
    menu.addItem(.separator())
    menu.addItem(item("Quit Voice", #selector(NSApplication.terminate), key: "q"))
  }

  /// Without a main menu, the settings window would not respond to ⌘W and ⌘Q.
  private func mainMenu() -> NSMenu {
    let menu = NSMenu()
    let app = NSMenu()
    app.addItem(item("Close Window", #selector(NSWindow.performClose), key: "w"))
    app.addItem(item("Quit Voice", #selector(NSApplication.terminate), key: "q"))
    let root = NSMenuItem()
    root.submenu = app
    menu.addItem(root)
    return menu
  }

  private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
    NSMenuItem(title: title, action: action, keyEquivalent: key)
  }

  @objc private func openSettings() {
    settingsWindow.show()
  }

  @objc private func openAccessibilitySettings() {
    Permissions.openPrivacySettings("Privacy_Accessibility")
  }

  @objc private func openMicrophoneSettings() {
    Permissions.openPrivacySettings("Privacy_Microphone")
  }
}
