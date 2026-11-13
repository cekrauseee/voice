import AppKit
import SwiftUI
import VoiceCore

/// The meetings, day by day, newest first. Clicking one opens its page.
struct MeetingsView: View {
  let meetings: [Meeting]
  let open: (Meeting.ID) -> Void
  let remove: (Meeting.ID) -> Void

  var body: some View {
    if meetings.isEmpty {
      empty
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Design.wide) {
          ForEach(meetings.days(in: .current)) { day in
            VStack(alignment: .leading, spacing: 2) {
              GroupTitle(title: day.date.dayTitle)
                .padding(.bottom, Design.tight)
              ForEach(day.meetings) { meeting in
                MeetingRow(meeting: meeting) {
                  open(meeting.id)
                } remove: {
                  remove(meeting.id)
                }
              }
            }
          }
        }
        .padding(Design.medium)
      }
    }
  }

  private var empty: some View {
    VStack(spacing: Design.small) {
      Image(systemName: "person.2.wave.2")
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(.tertiary)
      Text("No meetings yet")
        .font(.voiceTitle)
      Text("Start one from the menu bar")
        .font(.voiceCaption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// One meeting in the list: when it started, the start of what was said, and how long it
/// ran. One being recorded says so.
private struct MeetingRow: View {
  let meeting: Meeting
  let open: () -> Void
  let remove: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: open) {
      HStack(alignment: .firstTextBaseline, spacing: Design.medium) {
        Text(meeting.date.formatted(date: .omitted, time: .shortened))
          .font(.voiceCaption)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: 36, alignment: .leading)
        Group {
          if let first = meeting.paragraphs.first {
            Text(first.text)
          } else {
            Text(meeting.isLive ? "Recording…" : "Nothing transcribed")
              .foregroundStyle(.secondary)
          }
        }
        .font(.voiceBody)
        .lineLimit(3)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: Design.tight) {
          if meeting.isLive {
            Circle().fill(.red).frame(width: 6, height: 6)
          }
          Text(meeting.clock)
            .monospacedDigit()
        }
        .font(.voiceCaption)
        .foregroundStyle(.tertiary)
      }
      .padding(Design.small)
      .background(
        isHovered ? Design.hover : .clear,
        in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointer()
    .onHover { isHovered = $0 }
    .contextMenu {
      if !meeting.isEmpty { Button("Copy", action: copy) }
      if !meeting.isLive { Button("Delete", role: .destructive, action: remove) }
    }
  }

  private func copy() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(meeting.text, forType: .string)
  }
}

/// The page of one meeting: when it was, how long it ran, and the conversation, a
/// paragraph for each turn of it. While it is recorded, the text heard follows, dimmed,
/// and the page keeps to the end.
struct MeetingView: View {
  let meeting: Meeting
  let drafts: [Channel: String]

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: Design.large) {
          Text(summary)
            .font(.voiceCaption)
            .foregroundStyle(.secondary)
          if meeting.isEmpty && !meeting.isLive {
            Text("Nothing transcribed")
              .font(.voiceBody)
              .foregroundStyle(.secondary)
          }
          ForEach(meeting.paragraphs) { paragraph in
            ParagraphView(title: paragraph.channel.title, text: paragraph.text)
          }
          ForEach(Channel.allCases, id: \.self) { channel in
            if let draft = drafts[channel] {
              ParagraphView(title: channel.title, text: draft)
                .opacity(0.4)
            }
          }
          Color.clear.frame(height: 1).id("end")
        }
        .padding(Design.wide)
      }
      .onChange(of: meeting.segments.count, initial: true) { follow(proxy) }
      .onChange(of: drafts) { follow(proxy) }
    }
  }

  private func follow(_ proxy: ScrollViewProxy) {
    if meeting.isLive { proxy.scrollTo("end", anchor: .bottom) }
  }

  /// When it was, how long it ran, how many words it has, and what it cost.
  private var summary: String {
    var parts = [meeting.date.dateAndTime, meeting.clock]
    if !meeting.isEmpty {
      parts.append(meeting.words == 1 ? "1 word" : "\(meeting.words) words")
    }
    if meeting.usage.cost > 0 { parts.append(Figure.cost(meeting.usage.cost)) }
    return parts.joined(separator: "  ·  ")
  }
}

private struct ParagraphView: View {
  let title: String
  let text: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Design.medium) {
      Text(title)
        .font(.voiceCaption)
        .foregroundStyle(.secondary)
        .frame(width: 44, alignment: .leading)
      Text(text)
        .font(.voiceBody)
        .lineSpacing(3)
        .textSelection(.enabled)
        .pointer(.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
