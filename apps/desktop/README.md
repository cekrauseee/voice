# Desktop

The macOS menu bar app. It records while a shortcut says so, streams the audio to [the server](../server/README.md), shows the pill, and types the text that comes back into the focused field when the recording ends.

## Builds

There are two builds of the app. macOS tells them apart, so each has its own permissions and settings, and both can be installed at once.

|                 | Development                       | Production          |
| --------------- | --------------------------------- | ------------------- |
| Command         | `pnpm dev`                        | `pnpm build`        |
| App             | `build/Voice (Development).app`   | `build/Voice.app`   |
| Name            | Voice (Development)               | Voice               |
| Identifier      | `eu.cekrause.voice.dev`           | `eu.cekrause.voice` |
| Icon            | The waveform in amber, marked DEV | The waveform        |
| Compiled        | For debugging                     | Optimized           |
| In the menu bar | The waveform with a `DEV` mark    | The waveform        |

`pnpm dev` builds the development app, opens it, and prints its log until it quits. The app has no Dock icon: look for the waveform in the menu bar. Start the server too, or run `pnpm dev` at the repository root for both.

`pnpm build` only builds. `VERSION` sets the version of the app, which the release workflow takes from the tag.

The app connects to `ws://127.0.0.1:8787`. To use a server elsewhere, with the identifier of the build:

```sh
defaults write eu.cekrause.voice serverURL wss://voice.example.com
```

## Setup

The app needs two permissions:

| Permission    | Why                                                  |
| ------------- | ---------------------------------------------------- |
| Accessibility | To see the shortcuts in any app and to type the text |
| Microphone    | To record                                            |

On first launch a setup window takes the user through three steps, one at a time:

1. **Accessibility.** Open Settings adds the app to the Accessibility list in System Settings and opens that page. The user turns the app on there.
2. **Microphone.** Allow shows the macOS prompt.
3. **Try it.** A text field takes the focus. Holding the push-to-talk shortcut and speaking types into it.

The app follows the permissions as they change: a step is checked off the moment its permission is granted, and the window comes back in front of System Settings. While the window is open the app has a Dock icon, so the window is easy to find again. Done closes the setup, and is available once both permissions are granted.

The setup comes back on launch until it is completed, and whenever a permission is missing. While it is incomplete, the menu bar menu has a Finish Setup item.

### When a permission does not take effect

macOS ties a permission to the app's code signature. If the app is on in the Accessibility list but the step stays open, the entry belongs to a build signed differently. Remove the app from the list with −, then turn it on again. Or start over:

```sh
pnpm reset              # the development app
pnpm reset production   # the production app
```

This forgets the app's permissions and settings, so the next launch is a first launch.

The build signs with the first Apple Development identity in the keychain, which keeps the permissions across builds. Without one it signs ad hoc, and macOS asks again after every build. Set `CODESIGN_IDENTITY` to choose an identity.

## Using it

| Action           | Default | Behavior                                                                                                                            |
| ---------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Push to talk     | Right ⌥ | Records while held. A modifier key used as a shortcut still works as a modifier: pressing another key with it cancels the recording |
| Toggle recording | ⌥ Space | Starts recording, and stops it when pressed again                                                                                   |
| Cancel           | esc     | Drops the recording. Nothing is typed                                                                                               |

Recording starts the moment the shortcut is pressed. It does not wait for the server: audio recorded before the connection is up is sent once it is, also when the recording has already ended by then.

The text is typed once, when the recording ends and the server has refined it. If the dictation fails after words were recognized, they are typed as they were heard. Text is typed by pasting. The clipboard is restored afterwards.

## The window

The app lives in the menu bar. Its menu opens the app's window on one of its two sections:

- **Transcriptions**: what was dictated before, day by day, newest first. Each one shows when it was typed and how long the recording was, with its text cut at three lines. Clicking it shows all of the text, which can then be selected. Hovering shows a button to copy it, and the context menu deletes it.
- **Settings**: the settings below.

The window has one size and one button, which closes it: it cannot be minimized, zoomed, or made full screen. Beside that button is a header with the name of the section. The sections are in a sidebar under it, on the left. The button in the header, or ⌃⌘S, folds the sidebar to the icons alone and brings it back. The app remembers which.

The pointer shows what it is over: a hand over what can be clicked, the text cursor over text that can be selected or edited.

While the window is open, the app is also in the Dock and the app switcher, and it leaves them when the window closes. Opening the app again while it runs, from Finder or Spotlight, shows the window.

The past transcriptions are kept in `history.json`, in `~/Library/Application Support/` under the identifier of the build, so the two builds have separate histories. The file stays on the Mac: nothing but the app reads it, and its text is never logged. A transcription is kept when its text is typed, also when a dictation failed and the words were typed as heard. A cancelled dictation is not kept.

To work on the window without dictating first, fill the history of the development app with sample transcriptions:

```sh
pnpm seed
```

It keeps what the history holds, and running it again renews the samples. The app reads its history when it starts, so a running app is quit and opened again.

Settings:

- **Theme**: Auto, Light, or Dark.
- **Pill**: Minimal shows a small waveform. Detailed also shows the text as it is recognized, dimmed because it is not refined yet, and the shortcuts. Both styles type the same text at the same moment.
- **Shortcuts**: click a shortcut, then press the new one. A shortcut is a key with at least one modifier, a function key, or a single modifier key pressed alone.
- **Instructions**: how to write what you say, such as a tone, a language, or words to keep. They are added to the server's built-in instructions and take precedence over them. Empty by default.

## Microphone and media

The microphone is open only while a recording runs. Each recording opens it and releases it when it ends, so the app holds no audio device in between.

This matters with a Bluetooth headset used as the microphone. While its microphone is open, macOS switches the headset to call quality, which makes everything it plays sound flat. It goes back to normal a few seconds after the recording ends.

While a dictation runs, the media playing on the Mac is paused, and it resumes when the dictation is over. With a Bluetooth headset it resumes once the headset is out of call quality. Media that was not playing is left alone. This works with apps that macOS shows in Now Playing, such as music players and browsers. macOS has no public interface for another app's playback, so the app uses the system's private media remote: if a future macOS takes it away, media just keeps playing.

## The pill

The pill is one surface that changes shape. It grows out of its bottom edge when a dictation starts, and reshapes itself between the two styles and for a message, while the content dissolves from one to the other.

In the detailed style the pill shows the last three lines of the text as it is recognized. Each new word comes into focus where it lands. When the text outgrows three lines, all of it moves up a line: the oldest line goes out of focus through the top while the new one comes in at the bottom. With Reduce Motion on, or on macOS 14, the words just appear.

The waveform follows the voice from the center outward: the middle bars answer at once, and the level travels to the edges over half a second. While the text is being refined, a ripple runs through the bars. With Reduce Motion on, the bars only show the level, a few times a second.

| State     | Shown                                                                                                                                     |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Listening | The waveform follows the microphone                                                                                                       |
| Finishing | A rippling waveform. Recording ended, the text is being refined                                                                           |
| Failed    | A short message for three seconds: `Microphone access needed`, `No microphone found`, `Can't reach the server`, or `Transcription failed` |

## Logs

The app writes structured records to the macOS system log: see [logging](../../docs/logging.md). `pnpm dev` prints them as they happen:

```
16:22:47.830 INFO  permissions state accessibility=false microphone=undetermined
16:22:47.908 INFO  app         launched version=0.0.0 build=development
16:22:47.950 INFO  setup       step current=accessibility
```

Set `LOG_LEVEL=debug` to also see the detail of each dictation.

## Tests and lint

```sh
pnpm test          # builds the app and runs the tests
pnpm lint          # swift format, strict
pnpm format        # rewrites the Swift sources
pnpm check-types   # type-checks the scripts
```

The tests cover `VoiceCore`, which holds the logic that does not touch the system: shortcut matching, the transcript, the protocol, the setup steps, audio chunking, how the text streams in, the history, and when media is paused and resumed. The app target is thin glue over system APIs and is checked by building it and by hand.

## Layout

| Path                                                                | Responsibility                                                   |
| ------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `Sources/VoiceCore`                                                 | Logic without system dependencies                                |
| `Sources/Voice/AppDelegate.swift`                                   | Startup, the menu bar item, and the windows                      |
| `Sources/Voice/AppWindow.swift`                                     | A window, and the app being a regular app while one is open      |
| `Sources/Voice/MainView.swift`                                      | The app's window: the sections and the selected one              |
| `Sources/Voice/Design.swift`                                        | The measures, colors, and shared pieces the window is drawn with |
| `Sources/Voice/TranscriptionsView.swift`, `HistoryStore.swift`      | The past transcriptions, and the file that keeps them            |
| `Sources/Voice/Permissions.swift`                                   | The state of the two permissions                                 |
| `Sources/Voice/OnboardingView.swift`                                | The setup window                                                 |
| `Sources/Voice/HotkeyTap.swift`                                     | Watches the keyboard system-wide                                 |
| `Sources/Voice/DictationController.swift`                           | Runs a dictation from shortcut to typed text                     |
| `Sources/Voice/DictationSession.swift`                              | The WebSocket to the server                                      |
| `Sources/Voice/AudioCapture.swift`                                  | Records the microphone as 24 kHz PCM                             |
| `Sources/Voice/MediaControl.swift`                                  | Asks what media is playing, and pauses and resumes it            |
| `Sources/Voice/TextInserter.swift`                                  | Types text into the focused field                                |
| `Sources/Voice/PillPanel.swift`, `PillView.swift`, `Waveform.swift` | The pill                                                         |
| `Sources/Voice/TranscriptView.swift`                                | The text in the detailed pill, streaming in                      |
| `Sources/Voice/Settings*.swift`, `ShortcutField.swift`              | The settings                                                     |
| `Sources/Voice/Log.swift`, `AppInfo.swift`                          | Logging, and which build this is                                 |
| `Support/Info.plist`                                                | The app bundle's metadata                                        |
| `Support/AppIcon*.icns`, `scripts/icon.swift`                       | The icons of the two builds, and the script that draws them      |
| `scripts/variants.ts`                                               | The names and identifiers of the two builds                      |
| `scripts/bundle.ts`                                                 | Builds and signs the app                                         |
| `scripts/dev.ts`                                                    | Builds, runs, and prints the log                                 |
| `scripts/reset.ts`                                                  | Forgets the app's permissions and settings                       |
| `scripts/seed.ts`                                                   | Fills the development app's history with samples                 |
