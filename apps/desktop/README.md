# Desktop

The macOS menu bar app. It records while a shortcut says so, streams the audio to [the server](../server/README.md), shows the pill, and types the text that comes back into the focused field when the recording ends.

## Builds

There are two builds of the app. macOS tells them apart, so each has its own permissions and settings, and both can be installed at once.

|                 | Development                       | Production                       |
| --------------- | --------------------------------- | -------------------------------- |
| Command         | `pnpm dev`                        | `pnpm build`, `pnpm install-app` |
| App             | `build/Voice (Development).app`   | `build/Voice.dmg`                |
| Name            | Voice (Development)               | Voice                            |
| Identifier      | `eu.cekrause.voice.dev`           | `eu.cekrause.voice`              |
| Icon            | The waveform in amber, marked DEV | The waveform                     |
| Compiled        | For debugging                     | Optimized                        |
| In the menu bar | The waveform with a `DEV` mark    | The waveform                     |
| Server          | The one `pnpm dev` runs, at 8787  | Its own, at 8788                 |

`pnpm dev` builds the development app, opens it, and prints its log. Whenever the sources change it builds the app again and opens the new build, so the app that runs is always the current code. A build that fails leaves the running app alone. The app has no Dock icon: look for the waveform in the menu bar. Start the server too, or run `pnpm dev` at the repository root for both.

`pnpm build` builds the app and puts it in a disk image, `build/Voice.dmg`, with a link to Applications to drag it to. Only the image is kept, so Spotlight finds one Voice: the one installed. `VERSION` sets the version of the app, which the release workflow takes from the tag.

`pnpm install-app` installs the production app on this Mac, or updates it, from the checkout. It builds the app and the disk image the way a release does, quits the app if it runs, copies the app from the image to `/Applications`, and opens it. The version is what `git describe` says of the checkout: `0.1.0` on the tag `v0.1.0`, `0.1.0-2-g1a2b3c4` two commits after it. Built here, the app is signed like a development build, so it keeps its permissions from one update to the next.

## The server

The production app carries [the server](../server/README.md) and runs it on the Mac, at `ws://127.0.0.1:8788`. The two run together:

- Opening the app starts the server, however the app is opened: from Spotlight, at login, or by `pnpm install-app`.
- Quitting the app stops the server. If the app ends any other way, as in a crash, the server notices and stops too.
- If the server cannot start, or stops by itself, the app says why and quits.

The server runs with Node.js, installed with Homebrew or from nodejs.org (`/opt/homebrew/bin/node` or `/usr/local/bin/node`), and with the variables of `apps/server/.env`, the file `pnpm dev` uses: the OpenAI key, the models, the prices. The app sets the address and the port itself. `pnpm install-app` points the app at the `.env` of the repository's main checkout, also when it runs in another worktree, so a change to the file applies the next time the app opens. Without `pnpm install-app`, as from a release, set the file yourself:

```sh
defaults write eu.cekrause.voice serverEnvFile /path/to/.env
```

The server's records are in `~/Library/Logs/eu.cekrause.voice/server.log`, one JSON object per line, from its last start.

The development app does not run a server: it uses the one `pnpm dev` runs, at `ws://127.0.0.1:8787`. The two ports differ so that both apps can run at once.

To use a server elsewhere, set its address, with the identifier of the build. The production app then runs no server of its own:

```sh
defaults write eu.cekrause.voice serverURL wss://voice.example.com
```

## Setup

The app needs two permissions:

| Permission    | Why                                                  |
| ------------- | ---------------------------------------------------- |
| Accessibility | To see the shortcuts in any app and to type the text |
| Microphone    | To record                                            |

A third one, System Audio Recording, mutes the other apps while a dictation records. macOS asks for it the first time another app plays sound during a dictation. Without it, they keep playing.

On first launch a setup window takes the user through three steps, one at a time:

1. **Accessibility.** Open Settings adds the app to the Accessibility list in System Settings and opens that page. The user turns the app on there.
2. **Microphone.** Allow shows the macOS prompt.
3. **Try it.** A text field takes the focus. Holding the push-to-talk shortcut and speaking types into it.

Under the steps is Open at login, off by default. It is not a step: the setup is done without it, and it is the same setting as in the app's window.

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

The app lives in the menu bar. Its menu opens the app's window on one of its three sections:

- **Transcriptions**: what was dictated before, day by day, newest first. Each one shows when it was dictated, the start of its text, and how long the recording was. Clicking one opens its page, made for reading a long one: all of the text, which can be selected, and the recording, which can be played. The page's header has the way back, which Escape also takes, and buttons to copy and delete. In the list, hovering shows a button to copy a transcription, and the context menu deletes it.
- **Statistics**: how much was dictated today, in the last 7 days, in the last 30 days, or in all time: the words, the words per minute, the dictations, the time speaking, the tokens the refinement took, and an estimate of the cost. Under them is a chart of the words of each day: of each hour for today, and of each month once there are more than 90 days. Pointing at a bar shows when it is and its words.
- **Settings**: the settings below.

The window has one size and one button, which closes it: it cannot be minimized, zoomed, or made full screen. Beside that button is a header with the name of the section. The sections are in a sidebar under it, on the left. The button in the header, or ⌃⌘S, folds the sidebar to the icons alone and brings it back. The app remembers which.

The pointer shows what it is over: a hand over what can be clicked, the text cursor over text that can be selected or edited.

Almost nothing in the window moves: what is under the pointer, what is selected, and what a click shows change at once. Two things move, quickly, to say where something went: the page of a transcription comes in from the right, and the list comes back from the left, and the mark of a choice slides to the option chosen.

While the window is open, the app is also in the Dock and the app switcher, and it leaves them when the window closes. Opening the app again while it runs, from Finder or Spotlight, shows the window.

The past transcriptions are kept in `history.json`, and the recording of each one in `recordings/`, as a WAV file. Both are in `~/Library/Application Support/` under the identifier of the build, so the two builds have separate histories. They stay on the Mac: nothing but the app reads them, and their text is never logged. A dictation is kept when its text is typed. A cancelled one is not.

A dictation that fails is kept too, marked as failed, with whatever words came back. Its page has Try Again, which sends the recording to the server once more, so a failure does not lose what was said. The new text is not typed anywhere: it is in the history, to copy.

Recordings take about 3 MB a minute. The History setting deletes transcriptions and their recordings by themselves after 1 day, 7 days, or 30 days, or never, which is the default. The app does that itself, when it starts, when the setting changes, and every hour while it runs.

The statistics are kept in `statistics.json`, beside the history. They are figures by day, and by hour for the last day dictated on, never what was said. Each dictation that ends with its text is counted when it does, and so is a failed one that is tried again, so deleting a transcription, by hand or by the History setting, does not change them. The words per minute are the words typed over the time recorded. The tokens and the cost come from the server with each text. The cost is the server's estimate, from the prices in [its configuration](../server/README.md#configuration). A dictation that fails is not counted, though OpenAI may have charged for its audio.

To work on the window without dictating first, fill the history and the statistics of the development app with samples:

```sh
pnpm seed
```

Some samples have a recording, spoken by a system voice, and one of them failed, to try playing and trying again. It keeps what the history holds, and running it again renews the samples. The statistics get sample figures for the days of the last 30 that have none, today's spread over its hours: a day with figures is left as it is, so the samples stand beside what was really dictated. Deleting `statistics.json` removes them all. The app reads both files when it starts, so a running app is quit and opened again.

Settings:

- **Open at login**: macOS opens the app, in the menu bar, when you log in. Off by default. macOS keeps this, not the app: it is also in System Settings, under Login Items, and the two builds are separate items. If the app was turned off there, turning it on here opens that page.
- **Microphone**: the microphone to dictate with, chosen from a menu of the ones connected. System default, the default, follows the input chosen in macOS. A chosen microphone that is disconnected stays chosen: until it is connected again, the system default records.
- **Theme**: Auto, Light, or Dark.
- **Pill**: Minimal shows a small waveform. Detailed also shows the text as it is recognized, dimmed because it is not refined yet, and the shortcuts. Both styles type the same text at the same moment.
- **Pill position**: Bottom, the default, shows the pill at the bottom of the screen, above the Dock. Top shows it just under the menu bar, or, on a screen with a notch, out of the notch. Both styles go in either place.
- **Shortcuts**: click a shortcut, then press the new one. A shortcut is a key with at least one modifier, a function key, or a single modifier key pressed alone.
- **Instructions**: how to write what you say, such as a tone, a language, or words to keep. They are added to the server's built-in instructions and take precedence over them. Empty by default.
- **History**: how long transcriptions and their recordings are kept before they are deleted by themselves, chosen from a menu.

## Microphone and media

The microphone is the one chosen in the settings, or the input chosen in macOS. It is open only while a recording runs. Each recording opens it and releases it when it ends, so the app holds no audio device in between. Opening and closing the microphone wait for the device, so they happen behind the pill, which shows as soon as the shortcut is pressed. While the microphone opens and closes, the indicator macOS shows in the menu bar has a camera for a moment, whatever the app records with.

The Mac's own microphone delivers sound about a tenth of a second after it opens. A Bluetooth headset takes about a second, while it switches to call quality, and an iPhone almost as long. Until the sound comes, the pill says the microphone is starting, and what is said is not heard. The `recording` record in the log says when the sound came. With a headset on, choosing the Mac's own microphone in the settings starts faster and leaves the headset's sound as it is.

This matters with a Bluetooth headset used as the microphone, whether it is the one chosen or the system's. While its microphone is open, macOS switches the headset to call quality, which makes everything it plays sound flat. macOS leaves it there for two seconds after the microphone closes, so when a recording ends the app asks the headset for its best quality at once. It leaves call quality about a quarter of a second later, and plays again about a second after that, once its link is back: 1.2 seconds after the recording ends, instead of 3. While another app records, the headset is left alone.

While a dictation records, the media playing on the Mac is paused, and it resumes when the recording ends, without waiting for the text. With a Bluetooth headset it resumes once the headset plays again, so it comes back in full quality, about 1.2 seconds after the recording ends. The app knows by playing a moment of silence through the headset: starting it waits until the headset plays. Media that was not playing is left alone. This works with the app that macOS shows in Now Playing, such as a music player or a browser. macOS has no public interface for another app's playback, so the app uses the system's private media remote: if a future macOS takes it away, media just keeps playing.

Only that app can be paused. Another one keeps playing: a music player, say, while a browser holds Now Playing because it was played last. So while a dictation records, the other apps are muted, and they are heard again with the media, once the headset plays in full quality. What they play goes on meanwhile, unheard. The app mutes them with a Core Audio tap on their sound, from which it reads nothing, on macOS 14.2 or later. macOS takes that for recording: it asks for the System Audio Recording permission, and shows the app in the menu bar while the tap lasts. So it taps only while another app plays sound. If the app quits during a dictation, the tap goes, and the sound comes back by itself.

## The pill

The pill shows at the center of the screen the pointer is on, at the bottom or at the top, as the settings say. It is one surface that changes shape. It grows out of the edge of the screen it is at when a dictation starts, and reshapes itself between the two styles and for a message, while the content dissolves from one to the other.

At the top of a screen with a notch, the pill is part of the notch: black like it, it grows out of the notch when a dictation starts and goes back into it at the end. The minimal style spreads to either side of the notch and a little below it, with the microphone on the left and the waveform on the right. The detailed style and the messages drop down below it. The content comes and goes with it, in step. Its shape follows how far out of the notch it is: next to the notch it has the notch's corners, and away from it the pill's, so it closes back into the notch exactly, and the notch hides it whole once closed.

In the detailed style the pill shows the last three lines of the text as it is recognized. Each new word comes into focus where it lands. When the text outgrows three lines, all of it moves up a line: the oldest line goes out of focus through the top while the new one comes in at the bottom. With Reduce Motion on, or on macOS 14, the words just appear.

The waveform follows the voice from the center outward: the middle bars answer at once, and the level travels to the edges over half a second. While the microphone starts and while the text is being refined, the bars ripple, dimmed. The ripple comes and goes the way the voice does, in at the center and out through the edges, so one turns into the other without a jump. With Reduce Motion on, the bars only show the level, a few times a second, and dim instead of rippling.

| State     | Shown                                                                                                                                     |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Starting  | A rippling waveform, while the microphone starts and delivers no sound yet. What is said then is not heard                                |
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

The tests cover `VoiceCore`, which holds the logic that does not touch the system: shortcut matching, the transcript, the protocol, the setup steps, the choice of microphone, audio chunking, how the text streams in, the history, the statistics, when media is paused and resumed, and how the app runs its server. The app target is thin glue over system APIs and is checked by building it and by hand.

## Layout

| Path                                                                | Responsibility                                                   |
| ------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `Sources/VoiceCore`                                                 | Logic without system dependencies                                |
| `Sources/Voice/AppDelegate.swift`                                   | Startup, the menu bar item, and the windows                      |
| `Sources/Voice/AppWindow.swift`                                     | A window, and the app being a regular app while one is open      |
| `Sources/Voice/MainView.swift`                                      | The app's window: the sections and the selected one              |
| `Sources/Voice/Design.swift`                                        | The measures, colors, and shared pieces the window is drawn with |
| `Sources/Voice/TranscriptionsView.swift`, `TranscriptionView.swift` | The list of past transcriptions, and the page of one             |
| `Sources/Voice/HistoryStore.swift`                                  | The files that keep the past transcriptions and their recordings |
| `Sources/Voice/Retry.swift`, `Player.swift`                         | Transcribing a failed dictation again, and playing a recording   |
| `Sources/Voice/StatisticsView.swift`, `StatisticsStore.swift`       | The page of figures, and the file that keeps them                |
| `Sources/Voice/Permissions.swift`                                   | The state of the two permissions                                 |
| `Sources/Voice/LoginItem.swift`                                     | Whether macOS opens the app at login                             |
| `Sources/Voice/OnboardingView.swift`                                | The setup window                                                 |
| `Sources/Voice/HotkeyTap.swift`                                     | Watches the keyboard system-wide                                 |
| `Sources/Voice/DictationController.swift`                           | Runs a dictation from shortcut to typed text                     |
| `Sources/Voice/DictationSession.swift`                              | The WebSocket to the server                                      |
| `Sources/Voice/AudioCapture.swift`                                  | Records the microphone as 24 kHz PCM                             |
| `Sources/Voice/MediaControl.swift`                                  | Asks what media is playing, and pauses and resumes it            |
| `Sources/Voice/TextInserter.swift`                                  | Types text into the focused field                                |
| `Sources/Voice/ServerProcess.swift`                                 | Runs the server for the production app                           |
| `Sources/Voice/PillPanel.swift`, `PillView.swift`, `Waveform.swift` | The pill                                                         |
| `Sources/Voice/TranscriptView.swift`                                | The text in the detailed pill, streaming in                      |
| `Sources/Voice/Settings*.swift`, `ShortcutField.swift`              | The settings                                                     |
| `Sources/Voice/Log.swift`, `AppInfo.swift`                          | Logging, and which build this is                                 |
| `Support/Info.plist`                                                | The app bundle's metadata                                        |
| `Support/AppIcon*.icns`, `scripts/icon.swift`                       | The icons of the two builds, and the script that draws them      |
| `scripts/variants.ts`                                               | The names and identifiers of the two builds                      |
| `scripts/bundle.ts`                                                 | Builds and signs the app                                         |
| `scripts/dmg.ts`                                                    | Builds the production app and its disk image                     |
| `scripts/install.ts`                                                | Installs the production app in Applications, or updates it       |
| `scripts/quit.ts`                                                   | Quits an app and waits until it is gone                          |
| `scripts/dev.ts`                                                    | Builds, runs, and prints the log                                 |
| `scripts/reset.ts`                                                  | Forgets the app's permissions and settings                       |
| `scripts/seed.ts`                                                   | Fills the development app's history and statistics with samples  |
