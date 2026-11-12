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

/// The app's window: the sections on the left, and the one that is selected beside them.
struct MainView: View {
  @Bindable var navigation: Navigation
  let history: HistoryStore
  @Bindable var settings: Settings

  var body: some View {
    HStack(spacing: 0) {
      Sidebar(section: $navigation.section, isCollapsed: $settings.isSidebarCollapsed)
      Rectangle()
        .fill(Design.hairline)
        .frame(width: 1)
      VStack(alignment: .leading, spacing: 0) {
        // On the row of the window's buttons, like a window's own title.
        Text(navigation.section.title)
          .font(.voiceTitle)
          .frame(height: Design.barHeight)
          .padding(.horizontal, Design.large)
        switch navigation.section {
        case .transcriptions:
          TranscriptionsView(
            history: history.history, pushToTalk: settings.pushToTalk, remove: history.remove)
        case .settings:
          SettingsView(settings: settings)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    // The content reaches under the title bar, which only holds the window's buttons.
    .ignoresSafeArea(edges: .top)
    .animation(Design.morph, value: settings.isSidebarCollapsed)
  }
}

/// The sections, as icons with their names, or as icons alone when collapsed.
private struct Sidebar: View {
  @Binding var section: AppSection
  @Binding var isCollapsed: Bool

  var body: some View {
    VStack(spacing: 2) {
      ForEach(AppSection.allCases) { item in
        SidebarItem(
          title: item.title, symbol: item.symbol, isSelected: item == section,
          isCollapsed: isCollapsed
        ) {
          section = item
        }
      }
      Spacer(minLength: 0)
      SidebarItem(
        title: isCollapsed ? "Expand" : "Collapse", symbol: "sidebar.left", isSelected: false,
        isCollapsed: isCollapsed, isQuiet: true
      ) {
        isCollapsed.toggle()
      }
      .keyboardShortcut("s", modifiers: [.control, .command])
    }
    .padding(Design.small)
    // Below the window's buttons.
    .padding(.top, Design.barHeight)
    .frame(width: isCollapsed ? Design.railWidth : Design.sidebarWidth)
    .background(Design.surface)
    .clipped()
  }
}

private struct SidebarItem: View {
  let title: String
  let symbol: String
  let isSelected: Bool
  let isCollapsed: Bool
  /// Whether it is a control of the sidebar, not a section, and so drawn fainter.
  var isQuiet = false
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: Design.small) {
        Image(systemName: symbol)
          .font(.system(size: 13))
          .foregroundStyle(isSelected ? .primary : .secondary)
          .frame(width: 20)
        if !isCollapsed {
          Text(title)
            .font(.voiceLabel)
            .foregroundStyle(isQuiet ? .secondary : .primary)
            .lineLimit(1)
            .fixedSize()
            .transition(.opacity)
        }
      }
      .padding(.horizontal, Design.small)
      .frame(maxWidth: isCollapsed ? nil : .infinity, alignment: .leading)
      .frame(height: 28)
      .background(
        isSelected ? Design.selected : isHovered ? Design.hover : .clear,
        in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
      )
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(isCollapsed ? title : "")
    .accessibilityLabel(title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
