import SwiftUI
import VoiceCore

/// The profile page: a conversation with the agent on one side, and the profile it writes on
/// the other. The user talks with the shortcuts, and nothing on the page is typed: the
/// profile changes only through the conversation.
struct ProfileView: View {
  let settings: Settings
  let conversation: ProfileConversation
  /// The microphone's levels, while the user speaks.
  let levels: LevelFeed
  /// Whether the microphone is starting, and does not hear the user yet.
  let isMicrophoneStarting: Bool

  var body: some View {
    HStack(alignment: .top, spacing: Design.medium) {
      ConversationColumn(
        conversation: conversation.conversation, levels: levels,
        isMicrophoneStarting: isMicrophoneStarting, pushToTalk: settings.pushToTalk)
      ProfileColumn(
        profile: settings.profile,
        suggestions: settings.profile.pendingSuggestions(vocabulary: settings.vocabulary),
        accept: conversation.accept
      )
      .frame(width: 216)
    }
  }
}

/// The messages, newest at the bottom, and under them what is happening now.
private struct ConversationColumn: View {
  let conversation: Conversation
  let levels: LevelFeed
  let isMicrophoneStarting: Bool
  let pushToTalk: Shortcut

  private var isLive: Bool {
    conversation.state == .listening || conversation.state == .thinking
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { scroller in
        ScrollView {
          LazyVStack(spacing: Design.small) {
            ForEach(conversation.messages) { message in
              MessageView(
                message: message,
                isLive: isLive && message.id == conversation.messages.last?.id
                  && message.role == .user
              )
              .id(message.id)
            }
          }
          .padding(.horizontal, Design.medium)
          .padding(.vertical, Design.medium)
        }
        .defaultScrollAnchor(.bottom)
        .onChange(of: conversation.messages.last?.text) {
          if let last = conversation.messages.last?.id {
            scroller.scrollTo(last, anchor: .bottom)
          }
        }
      }
      status
        .frame(height: Design.control + Design.small)
        .padding(.horizontal, Design.medium)
    }
  }

  /// What is happening now: what to press, the microphone, the agent, or what went wrong.
  @ViewBuilder private var status: some View {
    HStack(spacing: Design.small) {
      switch conversation.state {
      case .idle:
        hint
      case .listening:
        Waveform(feed: levels, barCount: 7, isLoading: isMicrophoneStarting)
          .frame(width: 22, height: 14)
        Text(isMicrophoneStarting ? "Starting the microphone…" : "Listening…")
      case .thinking:
        Waveform(feed: levels, barCount: 7, isLoading: true)
          .frame(width: 22, height: 14)
        Text("Thinking…")
      case .replying:
        EmptyView()
      case .failed(let failure):
        // It says what to do: the shortcut is the one the user just held.
        Text(failure.message)
      }
      Spacer(minLength: 0)
    }
    .lineLimit(1)
    .font(.voiceCaption)
    .foregroundStyle(.secondary)
  }

  private var hint: some View {
    HStack(spacing: 5) {
      Text("Hold")
      KeyCaps(labels: pushToTalk.keyCaps)
      Text("to answer")
    }
  }
}

/// A message: the agent's on the left, the user's on the right, a note in the middle.
private struct MessageView: View {
  let message: Conversation.Message
  /// Whether it is what the user is saying now, still being heard.
  let isLive: Bool

  var body: some View {
    switch message.role {
    case .note:
      Text(message.text)
        .font(.voiceCaption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.tight)
    case .agent:
      bubble(fill: Design.surface)
        .padding(.trailing, Design.loose)
        .frame(maxWidth: .infinity, alignment: .leading)
    case .user:
      bubble(fill: Design.selected)
        .padding(.leading, Design.loose)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }

  private func bubble(fill: Color) -> some View {
    Text(message.text.isEmpty ? "…" : message.text)
      .font(.voiceBody)
      // What is still being heard is a draft, as in the pill.
      .foregroundStyle(isLive || message.text.isEmpty ? .secondary : .primary)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, Design.medium)
      .padding(.vertical, Design.small)
      .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

/// The profile as the agent wrote it, to read. It changes as the conversation goes.
private struct ProfileColumn: View {
  let profile: Profile
  let suggestions: [String]
  let accept: ([String]) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Design.wide) {
        if profile.isWritten {
          section("Writing") {
            paragraph(profile.instructions)
          }
        } else {
          section("Your profile") {
            paragraph("It is written here as you talk.")
          }
        }
        if !suggestions.isEmpty {
          section(
            "Suggested words",
            accessory: { TextButton(title: "Add All") { accept(suggestions) } }
          ) {
            FlowLayout(spacing: Design.tight) {
              ForEach(suggestions, id: \.self) { term in
                SuggestionChip(term: term) { accept([term]) }
              }
            }
            .padding(.horizontal, Design.small)
          }
        }
        if !profile.languages.isEmpty {
          section("Languages") {
            paragraph(profile.languageNames.joined(separator: ", "))
          }
        }
        if !profile.transcriptionPrompt.isEmpty {
          section("Listens for") {
            paragraph(profile.transcriptionPrompt)
          }
        }
      }
      .padding(.vertical, Design.medium)
      .padding(.trailing, Design.medium)
    }
  }

  private func paragraph(_ text: String) -> some View {
    Text(text)
      .font(.voiceCaption)
      .foregroundStyle(.secondary)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, Design.small)
  }

  private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
    section(title, accessory: { EmptyView() }, rows: rows)
  }

  private func section(
    _ title: String, @ViewBuilder accessory: () -> some View, @ViewBuilder rows: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: Design.tight) {
      HStack(spacing: Design.small) {
        GroupTitle(title: title)
        Spacer(minLength: 0)
        accessory()
      }
      rows()
    }
  }
}

/// A word suggested for the dictionary. A click adds it.
private struct SuggestionChip: View {
  let term: String
  let add: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: add) {
      HStack(spacing: Design.tight) {
        Text(term)
          .font(.voiceLabel)
          .lineLimit(1)
        Image(systemName: "plus")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, Design.small)
      .frame(height: 24)
      .background(
        isHovered ? Design.selected : Design.surface,
        in: RoundedRectangle(cornerRadius: Design.controlRadius + 1, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .pointer()
    .help("Add to Dictionary")
    .accessibilityLabel("Add \(term) to Dictionary")
    .contextMenu {
      Button("Add to Dictionary", action: add)
    }
  }
}

/// Lays its views out in rows, left to right, starting a new row when one is full.
private struct FlowLayout: Layout {
  var spacing: Double

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.map(\.height).reduce(0, +) + spacing * Double(max(rows.count - 1, 0))
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for row in rows(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width = 0.0
    var height = 0.0
  }

  private func rows(width: Double, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var row = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      if !row.indices.isEmpty, row.width + spacing + size.width > width {
        rows.append(row)
        row = Row()
      }
      row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      row.height = max(row.height, size.height)
      row.indices.append(index)
    }
    if !row.indices.isEmpty { rows.append(row) }
    return rows
  }
}
