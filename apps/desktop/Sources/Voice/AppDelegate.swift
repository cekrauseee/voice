import AppKit
import VoiceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let log = Log("app")
  private let settings = Settings()
  private let permissions = Permissions()
  private let history = HistoryStore()
  private let navigation = Navigation()
  private lazy var controller = DictationController(settings: settings, history: history)
  private lazy var hotkeys = HotkeyTap(settings: settings, controller: controller)
  private lazy var pill = PillPanel(controller: controller, settings: settings)
  private lazy var mainWindow = AppWindow(
    title: AppInfo.name,
    style: .main(size: NSSize(width: 680, height: 460)),
    content: MainView(navigation: navigation, history: history, settings: settings))
  private lazy var setupWindow = AppWindow(
    title: AppInfo.name,
    content: OnboardingContainer(permissions: permissions, settings: settings) { [weak self] in
      self?.finishSetup()
    })
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

  func applicationDidFinishLaunching(_ notification: Notification) {
    log.info(
      "launched",
      ["version": AppInfo.version, "build": AppInfo.isDevelopment ? "development" : "production"])

    NSApp.mainMenu = mainMenu()
    statusItem.button?.image = NSImage(
      systemSymbolName: "waveform", accessibilityDescription: AppInfo.name)
    if AppInfo.isDevelopment {
      // Tells the development build from the production one in the menu bar.
      statusItem.button?.title = "DEV"
      statusItem.button?.font = .systemFont(ofSize: 9, weight: .semibold)
      statusItem.button?.imagePosition = .imageLeading
    }
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

    track { [permissions] in
      permissions.accessibility
    } onChange: { [weak self] isGranted in
      if isGranted { self?.startShortcuts() }
      self?.surfaceSetup()
    }
    track { [permissions] in
      permissions.microphone
    } onChange: { [weak self] _ in
      self?.surfaceSetup()
    }
    if needsSetup { showSetup() }
  }

  /// The setup is shown until it is completed, and again whenever a permission is missing.
  private var needsSetup: Bool {
    !settings.hasOnboarded || !permissions.isComplete
  }

  private func showSetup() {
    setupWindow.onClose = { [log] in log.info("setup closed") }
    setupWindow.show()
    log.info("setup shown")
  }

  private func finishSetup() {
    settings.hasOnboarded = true
    log.info("setup completed")
    setupWindow.close()
  }

  /// A permission changed in System Settings: bring the setup back in front of it.
  private func surfaceSetup() {
    if setupWindow.isVisible { setupWindow.surface() }
  }

  private func startShortcuts() {
    if hotkeys.start() {
      log.info("shortcuts ready")
    } else {
      log.error("shortcuts unavailable", ["hint": "quit and reopen the app"])
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    // Every item has an icon, so their names line up. A section has the icon it has in the
    // window's sidebar.
    if needsSetup {
      menu.addItem(item("Finish Setup…", #selector(openSetup), symbol: "checklist"))
      menu.addItem(.separator())
    }
    let (transcriptions, settings) = (AppSection.transcriptions, AppSection.settings)
    menu.addItem(
      item(transcriptions.title, #selector(openTranscriptions), symbol: transcriptions.symbol))
    menu.addItem(
      item("\(settings.title)…", #selector(openSettings), key: ",", symbol: settings.symbol))
    menu.addItem(.separator())
    menu.addItem(
      item(
        "Quit \(AppInfo.name)", #selector(NSApplication.terminate), key: "q", symbol: "power"))
  }

  /// The app was opened again while it runs, from Finder, Spotlight, or the Dock.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    if needsSetup { showSetup() } else { mainWindow.show() }
    return false
  }

  /// The windows need a main menu for the standard shortcuts, such as ⌘V and ⌘W.
  private func mainMenu() -> NSMenu {
    let app = NSMenu()
    app.addItem(item("Settings…", #selector(openSettings), key: ","))
    app.addItem(.separator())
    app.addItem(item("Quit \(AppInfo.name)", #selector(NSApplication.terminate), key: "q"))

    let file = NSMenu(title: "File")
    file.addItem(item("Close Window", #selector(NSWindow.performClose), key: "w"))

    let edit = NSMenu(title: "Edit")
    edit.addItem(item("Undo", Selector(("undo:")), key: "z"))
    edit.addItem(item("Redo", Selector(("redo:")), key: "Z"))
    edit.addItem(.separator())
    edit.addItem(item("Cut", #selector(NSText.cut), key: "x"))
    edit.addItem(item("Copy", #selector(NSText.copy), key: "c"))
    edit.addItem(item("Paste", #selector(NSText.paste), key: "v"))
    edit.addItem(item("Select All", #selector(NSText.selectAll), key: "a"))

    let menu = NSMenu()
    for submenu in [app, file, edit] {
      let root = NSMenuItem()
      root.submenu = submenu
      menu.addItem(root)
    }
    return menu
  }

  private func item(
    _ title: String, _ action: Selector, key: String = "", symbol: String? = nil
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    if let symbol {
      item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
    return item
  }

  @objc private func openTranscriptions() {
    open(.transcriptions)
  }

  @objc private func openSettings() {
    open(.settings)
  }

  private func open(_ section: AppSection) {
    navigation.section = section
    mainWindow.show()
  }

  @objc private func openSetup() {
    showSetup()
  }
}
