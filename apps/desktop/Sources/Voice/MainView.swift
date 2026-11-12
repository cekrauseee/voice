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
  let settings: Settings

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      VStack(alignment: .leading, spacing: 0) {
        Text(navigation.section.title)
          .font(.title2.bold())
          .padding(.horizontal, 20)
          .padding(.top, 40)
          .padding(.bottom, 4)
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
  }

  private var sidebar: some View {
    VStack(spacing: 2) {
      ForEach(AppSection.allCases) { section in
        Button {
          navigation.section = section
        } label: {
          Label(section.title, systemImage: section.symbol)
            .labelStyle(SidebarLabelStyle())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              .primary.opacity(navigation.section == section ? 0.1 : 0),
              in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
    .padding(.horizontal, 10)
    // Below the window's buttons.
    .padding(.top, 52)
    .frame(width: 190)
    .background(.primary.opacity(0.04))
  }
}

private struct SidebarLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 8) {
      configuration.icon
        .foregroundStyle(.secondary)
        .frame(width: 18)
      configuration.title
    }
    .font(.system(size: 13, weight: .medium))
  }
}
