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

/// Which section the window is on. The menus set it before they show the window.
@MainActor @Observable
final class Navigation {
  var section = AppSection.transcriptions
}

/// The app's window: a header beside the window's buttons, and under it the sections on the
/// left and the selected one beside them.
struct MainView: View {
  @Bindable var navigation: Navigation
  let history: HistoryStore
  @Bindable var settings: Settings

  @Environment(\.windowButtonsWidth) private var windowButtonsWidth

  var body: some View {
    GeometryReader { window in
      VStack(spacing: 0) {
        // As tall as the title bar, which only holds the window's buttons.
        header
          .frame(height: window.safeAreaInsets.top)
        Rectangle()
          .fill(Design.hairline)
          .frame(height: 1)
        HStack(spacing: 0) {
          Sidebar(section: $navigation.section, isCollapsed: settings.isSidebarCollapsed)
          Rectangle()
            .fill(Design.hairline)
            .frame(width: 1)
          Group {
            switch navigation.section {
            case .transcriptions:
              TranscriptionsView(
                history: history.history, pushToTalk: settings.pushToTalk, remove: history.remove
              )
            case .settings:
              SettingsView(settings: settings)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
      .ignoresSafeArea(edges: .top)
    }
    .animation(Design.morph, value: settings.isSidebarCollapsed)
  }

  /// The button that folds the sidebar, and the name of the section.
  private var header: some View {
    HStack(spacing: Design.small) {
      IconButton(
        symbol: "sidebar.left", help: settings.isSidebarCollapsed ? "Show Sidebar" : "Hide Sidebar"
      ) {
        settings.isSidebarCollapsed.toggle()
      }
      .keyboardShortcut("s", modifiers: [.control, .command])
      Text(navigation.section.title)
        .font(.voiceTitle)
      Spacer(minLength: 0)
    }
    .padding(.leading, windowButtonsWidth + Design.medium)
    .padding(.trailing, Design.large)
  }
}

/// The sections, as icons with their names, or as icons alone when collapsed.
private struct Sidebar: View {
  @Binding var section: AppSection
  let isCollapsed: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(AppSection.allCases) { item in
        SidebarItem(
          title: item.title, symbol: item.symbol, isSelected: item == section,
          isCollapsed: isCollapsed
        ) {
          section = item
        }
      }
      Spacer(minLength: 0)
    }
    .padding(Design.small)
    .frame(width: isCollapsed ? Design.railWidth : Design.sidebarWidth, alignment: .leading)
    .clipped()
  }
}

/// A section in the sidebar. Its icon stays where it is when the sidebar folds.
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
            .fixedSize()
            .transition(.opacity)
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
