# Desktop

The macOS menu bar app. It records while a shortcut says so, streams the audio to [the server](../server/README.md), shows the pill, and types the text that comes back into the focused field.

## Running

```sh
pnpm dev
```

This builds `build/Voice.app`, opens it, and prints its log until it quits. The app has no Dock icon: look for the waveform in the menu bar. Start the server too, or run `pnpm dev` at the repository root for both.

The app connects to `ws://127.0.0.1:8787`. To use a server elsewhere:

```sh
defaults write eu.cekrause.voice serverURL wss://voice.example.com
```

## Permissions

| Permission    | Why                                                  | When macOS asks        |
| ------------- | ---------------------------------------------------- | ---------------------- |
| Accessibility | To see the shortcuts in any app and to type the text | On first launch        |
| Microphone    | To record                                            | On the first dictation |

The shortcuts do nothing until Accessibility access is granted. The app keeps checking, so they start working once it is. If they do not, quit and reopen the app. While a permission is missing, the menu bar menu has an item that opens the right page of System Settings.

macOS ties these permissions to the app's code signature. The build signs with the first Apple Development identity in the keychain, which keeps the permissions across builds. Without one it signs ad hoc, and macOS asks again after every build. Set `CODESIGN_IDENTITY` to choose an identity.

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

## Tests and lint

```sh
pnpm test     # builds the app and runs the tests
pnpm lint     # swift format, strict
pnpm format   # rewrites the sources
```

The tests cover `VoiceCore`, which holds the logic that does not touch the system: shortcut matching, the transcript, the protocol, and audio chunking. The app target is thin glue over system APIs and is checked by building it and by hand.

## Layout

| Path                                                                | Responsibility                               |
| ------------------------------------------------------------------- | -------------------------------------------- |
| `Sources/VoiceCore`                                                 | Logic without system dependencies            |
| `Sources/Voice/AppDelegate.swift`                                   | The menu bar item and app startup            |
| `Sources/Voice/HotkeyTap.swift`                                     | Watches the keyboard system-wide             |
| `Sources/Voice/DictationController.swift`                           | Runs a dictation from shortcut to typed text |
| `Sources/Voice/DictationSession.swift`                              | The WebSocket to the server                  |
| `Sources/Voice/AudioCapture.swift`                                  | Records the microphone as 24 kHz PCM         |
| `Sources/Voice/TextInserter.swift`                                  | Types text into the focused field            |
| `Sources/Voice/PillPanel.swift`, `PillView.swift`, `Waveform.swift` | The pill                                     |
| `Sources/Voice/Settings*.swift`, `ShortcutField.swift`              | The settings and their window                |
| `Support/Info.plist`                                                | The app bundle's metadata                    |
| `scripts/bundle.sh`                                                 | Builds and signs `build/Voice.app`           |
