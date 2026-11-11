# Desktop

The macOS menu bar app. It records while a shortcut says so, streams the audio to [the server](../server/README.md), shows the pill, and types the text that comes back into the focused field.

## Builds

There are two builds of the app. macOS tells them apart, so each has its own permissions and settings, and both can be installed at once.

|                 | Development                    | Production          |
| --------------- | ------------------------------ | ------------------- |
| Command         | `pnpm dev`                     | `pnpm build`        |
| App             | `build/Voice Dev.app`          | `build/Voice.app`   |
| Name            | Voice Dev                      | Voice               |
| Identifier      | `eu.cekrause.voice.dev`        | `eu.cekrause.voice` |
| Compiled        | For debugging                  | Optimized           |
| In the menu bar | The waveform with a `DEV` mark | The waveform        |

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
| Cancel           | esc     | Drops the recording and any text that has not been typed                                                                            |

Text is typed by pasting. The clipboard is restored afterwards.

Settings, from the menu bar menu:

- **Theme**: Auto, Light, or Dark.
- **Pill**: Minimal shows a small waveform. Detailed also shows the text as it is recognized, dimmed until it is refined, and the shortcuts.
- **Shortcuts**: click a shortcut, then press the new one. A shortcut is a key with at least one modifier, a function key, or a single modifier key pressed alone.

## The pill

| State      | Shown                                                                                                                                     |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Connecting | A rippling waveform. Recording has started, the server is getting ready                                                                   |
| Listening  | The waveform follows the microphone                                                                                                       |
| Finishing  | A rippling waveform. Recording ended, the last text is on its way                                                                         |
| Failed     | A short message for three seconds: `Microphone access needed`, `No microphone found`, `Can't reach the server`, or `Transcription failed` |

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

The tests cover `VoiceCore`, which holds the logic that does not touch the system: shortcut matching, the transcript, the protocol, the setup steps, and audio chunking. The app target is thin glue over system APIs and is checked by building it and by hand.

## Layout

| Path                                                                | Responsibility                               |
| ------------------------------------------------------------------- | -------------------------------------------- |
| `Sources/VoiceCore`                                                 | Logic without system dependencies            |
| `Sources/Voice/AppDelegate.swift`                                   | Startup, the menu bar item, and the windows  |
| `Sources/Voice/Permissions.swift`                                   | The state of the two permissions             |
| `Sources/Voice/OnboardingView.swift`                                | The setup window                             |
| `Sources/Voice/HotkeyTap.swift`                                     | Watches the keyboard system-wide             |
| `Sources/Voice/DictationController.swift`                           | Runs a dictation from shortcut to typed text |
| `Sources/Voice/DictationSession.swift`                              | The WebSocket to the server                  |
| `Sources/Voice/AudioCapture.swift`                                  | Records the microphone as 24 kHz PCM         |
| `Sources/Voice/TextInserter.swift`                                  | Types text into the focused field            |
| `Sources/Voice/PillPanel.swift`, `PillView.swift`, `Waveform.swift` | The pill                                     |
| `Sources/Voice/Settings*.swift`, `ShortcutField.swift`              | The settings                                 |
| `Sources/Voice/Log.swift`, `AppInfo.swift`                          | Logging, and which build this is             |
| `Support/Info.plist`                                                | The app bundle's metadata                    |
| `scripts/variants.ts`                                               | The names and identifiers of the two builds  |
| `scripts/bundle.ts`                                                 | Builds and signs the app                     |
| `scripts/dev.ts`                                                    | Builds, runs, and prints the log             |
| `scripts/reset.ts`                                                  | Forgets the app's permissions and settings   |
