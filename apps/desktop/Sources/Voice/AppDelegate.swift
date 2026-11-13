import AppKit
import VoiceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let log = Log("app")
  private let settings = Settings()
  private let permissions = Permissions()
  private let history = HistoryStore()
  private let meetings = MeetingStore()
  private let statistics = StatisticsStore()
  private let navigation = Navigation()
  private let loginItem = LoginItem()
  private lazy var server = ServerProcess()
  private lazy var controller = DictationController(
    settings: settings, history: history, statistics: statistics)
  private lazy var retry = Retry(settings: settings, history: history, statistics: statistics)
  private lazy var meeting = MeetingController(settings: settings, store: meetings)
  private lazy var hotkeys = HotkeyTap(settings: settings, controller: controller)
  private lazy var pill = PillPanel(controller: controller, meeting: meeting, settings: settings) {
    [weak self] in
    guard let self, let id = meeting.live?.meeting.id else { return }
    navigation.show(meeting: id)
    mainWindow.show()
  }
  private lazy var mainWindow = AppWindow(
    title: AppInfo.name,
    style: .main(size: NSSize(width: 680, height: 460)),
    content: MainView(
      navigation: navigation, history: history, meetings: meetings, meeting: meeting,
      statistics: statistics, retry: retry, loginItem: loginItem, settings: settings))
  private lazy var setupWindow = AppWindow(
    title: AppInfo.name,
    content: OnboardingContainer(
      permissions: permissions, settings: settings, loginItem: loginItem
    ) { [weak self] in
      self?.finishSetup()
    })
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

  func applicationDidFinishLaunching(_ notification: Notification) {
    log.info(
      "launched",
      ["version": AppInfo.version, "build": AppInfo.isDevelopment ? "development" : "production"])
    if settings.runsServer { startServer() }

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
    track { [settings] in
      settings.detectsMeetings
    } onChange: { [weak self] detecting in
      self?.meeting.start(detecting: detecting)
    }

    // Transcriptions older than they are kept for are deleted when the app starts, when
    // the setting changes, and every hour while the app runs.
    track { [settings] in
      settings.retention
    } onChange: { [history, meetings] retention in
      history.prune(retention)
      meetings.prune(retention)
    }
    Task { [settings, history, meetings] in
      while true {
        try? await Task.sleep(for: .seconds(3600))
        history.prune(settings.retention)
        meetings.prune(settings.retention)
      }
    }

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

  /// The app and its server run together: when the server cannot start, or stops by itself, the
  /// app says why and quits.
  private func startServer() {
    do {
      try server.start(environmentFile: settings.serverEnvFile) { [weak self] failure in
        self?.quit(failure)
      }
    } catch {
      quit(error)
    }
  }

  private func quit(_ failure: ServerProcess.Failure) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = failure.title
    alert.informativeText = failure.detail
    alert.addButton(withTitle: "Quit")
    alert.runModal()
    NSApp.terminate(nil)
  }

  func applicationWillTerminate(_ notification: Notification) {
    if settings.runsServer { server.stop() }
    history.flush()
    statistics.flush()
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
    if meeting.isRecording {
      menu.addItem(item("Stop Meeting", #selector(stopMeeting), symbol: "stop.circle"))
    } else {
      menu.addItem(item("Start Meeting", #selector(startMeeting), symbol: "record.circle"))
    }
    menu.addItem(.separator())
    let (transcriptions, meetings, statistics, settings) = (
      AppSection.transcriptions, AppSection.meetings, AppSection.statistics, AppSection.settings
    )
    menu.addItem(
      item(transcriptions.title, #selector(openTranscriptions), symbol: transcriptions.symbol))
    menu.addItem(item(meetings.title, #selector(openMeetings), symbol: meetings.symbol))
    menu.addItem(item(statistics.title, #selector(openStatistics), symbol: statistics.symbol))
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

  @objc private func openMeetings() {
    open(.meetings)
  }

  @objc private func openStatistics() {
    open(.statistics)
  }

  /// Starts recording a meeting, and opens its page.
  @objc private func startMeeting() {
    meeting.start()
    if let id = meeting.live?.meeting.id {
      navigation.show(meeting: id)
      mainWindow.show()
    }
  }

  @objc private func stopMeeting() {
    meeting.stop()
  }

  @objc private func openSettings() {
    open(.settings)
  }

  private func open(_ section: AppSection) {
    navigation.show(section)
    mainWindow.show()
  }

  @objc private func openSetup() {
    showSetup()
  }
}
