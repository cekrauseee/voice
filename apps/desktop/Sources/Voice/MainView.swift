import AppKit
import Observation
import SwiftUI
import VoiceCore

/// A section of the app's window.
enum AppSection: String, CaseIterable, Identifiable {
  case transcriptions
  case settings

  var id: Self { self }

  var title: String {
    switch self {
    case .transcriptions: "Transcriptions"
    case .settings: "Settings"
    }
  }

  var symbol: String {
    switch self {
    case .transcriptions: "text.quote"
    case .settings: "gearshape"
    }
  }
}

/// Where the window is: on which section, and on which of its pages.
@MainActor @Observable
final class Navigation {
  private(set) var section = AppSection.transcriptions
  /// The transcription that is open on its own page, if one is.
  var transcription: Transcription.ID?

  /// Goes to a section, on its first page.
  func show(_ section: AppSection) {
    self.section = section
    transcription = nil
  }
}

/// The app's window: a header beside the button that closes it, and under it the sections
/// on the left and the selected one beside them.
struct MainView: View {
  let navigation: Navigation
  let history: HistoryStore
  @Bindable var settings: Settings

  @Environment(\.windowButtonsWidth) private var windowButtonsWidth
  @State private var didCopy = false
  @State private var isDeleting = false

  var body: some View {
    GeometryReader { window in
      VStack(spacing: 0) {
        // As tall as the title bar, which only holds the button that closes the window.
        header
          .frame(height: window.safeAreaInsets.top)
        Rectangle()
          .fill(Design.hairline)
          .frame(height: 1)
        HStack(spacing: 0) {
          Sidebar(
            section: navigation.section, isCollapsed: settings.isSidebarCollapsed,
            select: navigation.show)
          Rectangle()
            .fill(Design.hairline)
            .frame(width: 1)
          Group {
            switch navigation.section {
            case .transcriptions: transcriptions
            case .settings: SettingsView(settings: settings)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
      .ignoresSafeArea(edges: .top)
    }
  }

  /// The transcription that is open on its own page, if it is still in the history.
  private var open: Transcription? {
    guard navigation.section == .transcriptions else { return nil }
    return history.history.transcriptions.first { $0.id == navigation.transcription }
  }

  /// The list, and over it the page of the transcription that is open.
  ///
  /// What is left goes at once, and what is come to moves in: the page from the right,
  /// the list from the left. So only one of them is ever seen, and it is clear which way
  /// it went.
  private var transcriptions: some View {
    ZStack {
      // The list stays under the page, to be where it was left on the way back.
      TranscriptionsView(
        history: history.history, pushToTalk: settings.pushToTalk,
        open: { navigation.transcription = $0 }, remove: history.remove
      )
      .opacity(open == nil ? 1 : 0)
      .offset(x: open == nil ? 0 : -Design.large)
      .animation(open == nil ? Design.move : nil, value: open?.id)
      .allowsHitTesting(open == nil)
      .accessibilityHidden(open != nil)
      if let open {
        TranscriptionView(transcription: open)
          .transition(
            .asymmetric(
              insertion: .offset(x: Design.large).combined(with: .opacity), removal: .identity))
      }
    }
    .animation(Design.move, value: open?.id)
  }

  /// The button that folds the sidebar, then the name of the section, or the way back
  /// from a transcription and what can be done with it.
  private var header: some View {
    HStack(spacing: Design.small) {
      // Buttons that are icons stand close together, as one group.
      HStack(spacing: 2) {
        IconButton(
          symbol: "sidebar.left",
          help: settings.isSidebarCollapsed ? "Show Sidebar" : "Hide Sidebar"
        ) {
          settings.isSidebarCollapsed.toggle()
        }
        .keyboardShortcut("s", modifiers: [.control, .command])
        if open != nil {
          IconButton(symbol: "chevron.left", help: "Back") { navigation.transcription = nil }
            .keyboardShortcut(.cancelAction)
        }
      }
      Text(open?.date.dayAndTime ?? navigation.section.title)
        .font(.voiceTitle)
      Spacer(minLength: 0)
      if let open {
        HStack(spacing: 2) {
          IconButton(symbol: didCopy ? "checkmark" : "doc.on.doc", help: "Copy") { copy(open) }
          IconButton(symbol: "trash", help: "Delete") { isDeleting = true }
            .confirmationDialog("Delete this transcription?", isPresented: $isDeleting) {
              Button("Delete", role: .destructive) { history.remove(open.id) }
            }
        }
      }
    }
    .padding(.leading, windowButtonsWidth + Design.small)
    .padding(.trailing, Design.small)
  }

  private func copy(_ transcription: Transcription) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(transcription.text, forType: .string)
    didCopy = true
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      didCopy = false
    }
  }
}

/// The sections, as icons with their names, or as icons alone when folded.
private struct Sidebar: View {
  let section: AppSection
  let isCollapsed: Bool
  let select: (AppSection) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(AppSection.allCases) { item in
        SidebarItem(
          title: item.title, symbol: item.symbol, isSelected: item == section,
          isCollapsed: isCollapsed
        ) {
          select(item)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Design.tight)
    .padding(.vertical, Design.small)
    .frame(width: isCollapsed ? Design.railWidth : Design.sidebarWidth, alignment: .leading)
  }
}

/// A section in the sidebar. Its icon is in the same place whether the sidebar is folded
/// or not.
private struct SidebarItem: View {
  let title: String
  let symbol: String
  let isSelected: Bool
  let isCollapsed: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 2) {
        Image(systemName: symbol)
          .font(.system(size: 13))
          .foregroundStyle(isSelected ? .primary : .secondary)
          .frame(width: Design.control, height: Design.control)
        if !isCollapsed {
          Text(title)
            .font(.voiceLabel)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: isCollapsed ? nil : .infinity, alignment: .leading)
      .background(
        isSelected ? Design.selected : isHovered ? Design.hover : .clear,
        in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .pointer()
    .help(isCollapsed ? title : "")
    .accessibilityLabel(title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// A button that is an icon, with a quiet highlight under the pointer.
struct IconButton: View {
  let symbol: String
  let help: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(width: Design.control, height: Design.control)
        .background(
          isHovered ? Design.hover : .clear,
          in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .pointer()
    .help(help)
    .accessibilityLabel(help)
  }
}

extension Date {
  /// The day as the window names it: today, yesterday, or the date.
  ///
  /// In English, like the rest of the app, whatever language the Mac is in.
  var dayTitle: String {
    let calendar = Calendar.current
    if calendar.isDateInToday(self) { return "Today" }
    if calendar.isDateInYesterday(self) { return "Yesterday" }
    let isThisYear = calendar.isDate(self, equalTo: .now, toGranularity: .year)
    let format = Date.FormatStyle(locale: Locale(identifier: "en_US"))
      .weekday(.wide).day().month(.wide)
    return formatted(isThisYear ? format : format.year())
  }

  /// The day and the time, such as `Today at 10:42`.
  var dayAndTime: String {
    "\(dayTitle) at \(formatted(date: .omitted, time: .shortened))"
  }

  /// The whole date and the time, such as `Thursday, November 12, 2026 at 10:42`.
  var dateAndTime: String {
    let format = Date.FormatStyle(locale: Locale(identifier: "en_US"))
      .weekday(.wide).day().month(.wide).year()
    return "\(formatted(format)) at \(formatted(date: .omitted, time: .shortened))"
  }
}
