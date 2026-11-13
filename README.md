# Voice

Real-time voice dictation for macOS. Hold a key, speak, and when you let go the text is typed into the field you are in, cleaned up the way you want it written.

- `apps/desktop`: the macOS menu bar app. It records, shows the pill, and types the text.
- `apps/server`: the service that transcribes and refines the speech with OpenAI.
- `packages/log`: the structured logger both use.

## Requirements

- A Mac with Xcode 26 or later. The app targets macOS 14 and later
- Node.js 26 and pnpm 11
- An [OpenAI API key](https://platform.openai.com/api-keys)

## Getting started

```sh
pnpm dev
```

`pnpm dev` prepares what is missing, then runs both apps:

1. It installs the dependencies.
2. It creates `apps/server/.env` from `.env.example`. Add your `OPENAI_API_KEY` there: the server waits for it and starts as soon as the file is saved.
3. It builds and opens the development app, Voice (Development), which lives in the menu bar.

While it runs, a change to the code restarts the server, and builds and reopens the app.

Each app has its own log in the terminal, as [structured records](docs/logging.md): move between them with the arrow keys, and quit with Ctrl-C.

Running it again changes nothing you have set: variables added to `.env.example` later are added to your `.env`, and existing values are kept.

On first launch the app opens a setup window that takes you through the two permissions it needs and lets you try a dictation: see [the desktop README](apps/desktop/README.md#setup).

Then dictate:

| Action                                                | Default shortcut |
| ----------------------------------------------------- | ---------------- |
| Push to talk: hold to record, release when done       | Right ⌥          |
| Toggle recording: press to start, press again to stop | ⌥ Space          |
| Cancel                                                | esc              |

While holding push to talk, press Space to keep recording after you release the shortcut. Use Toggle recording to stop, or esc to cancel.

Clicking Voice in the menu bar shows today's words and the last transcriptions, and opens the app's window: the past transcriptions, which can be searched, the statistics of what was dictated and what it cost, and the settings.

## Using it every day

`pnpm dev` is for working on Voice. To use it, install the production app:

```sh
pnpm install-app
```

It builds Voice, puts it in Applications, and opens it. Voice runs its own server, with the OpenAI key in `apps/server/.env`: opening the app starts the server, and quitting it stops the server. Run the command again to update the app. See [the desktop README](apps/desktop/README.md#the-server).

## Commands

| Command            | What it does                                                        |
| ------------------ | ------------------------------------------------------------------- |
| `pnpm dev`         | Runs the server and the app                                         |
| `pnpm verify`      | Checks formatting, lint, types, and tests. CI runs the same command |
| `pnpm format`      | Formats the TypeScript and Swift sources                            |
| `pnpm test`        | Runs the tests                                                      |
| `pnpm build`       | Builds the app into a disk image, `apps/desktop/build/Voice.dmg`    |
| `pnpm install-app` | Installs the app in Applications, or updates it, from this checkout |

Add `--filter @voice/server` or `--filter @voice/desktop` to `pnpm dev` or `pnpm test` to run one app.

## Documentation

- [Architecture](docs/architecture.md): how speech becomes typed text, and why it is built this way
- [Protocol](docs/protocol.md): the contract between the app and the server
- [Logging](docs/logging.md): the form every log record takes
- [Releasing](docs/releasing.md): how a version is published
- [Server](apps/server/README.md): configuration, tuning, and tools
- [Desktop](apps/desktop/README.md): permissions, settings, and signing
