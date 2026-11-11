# Voice

Real-time voice dictation for macOS. Hold a key, speak, and the text is typed into the field you are in, cleaned up sentence by sentence while you keep talking.

- `apps/desktop`: the macOS menu bar app. It records, shows the pill, and types the text.
- `apps/server`: the service that transcribes and refines the speech with OpenAI.

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
3. It builds and opens the app, which lives in the menu bar.

Running it again changes nothing you have set: variables added to `.env.example` later are added to your `.env`, and existing values are kept.

On first launch macOS asks for Accessibility access, and for microphone access on the first dictation: see [the desktop README](apps/desktop/README.md#permissions).

Then dictate:

| Action                                                | Default shortcut |
| ----------------------------------------------------- | ---------------- |
| Push to talk: hold to record, release when done       | Right ⌥          |
| Toggle recording: press to start, press again to stop | ⌥ Space          |
| Cancel                                                | esc              |

## Commands

| Command       | What it does                                                        |
| ------------- | ------------------------------------------------------------------- |
| `pnpm dev`    | Runs the server and the app                                         |
| `pnpm verify` | Checks formatting, lint, types, and tests. CI runs the same command |
| `pnpm format` | Formats the TypeScript and Swift sources                            |
| `pnpm test`   | Runs the tests                                                      |
| `pnpm build`  | Builds `apps/desktop/build/Voice.app` for release                   |

Add `--filter @voice/server` or `--filter @voice/desktop` to `pnpm dev` or `pnpm test` to run one app.

## Documentation

- [Architecture](docs/architecture.md): how speech becomes typed text, and why it is built this way
- [Protocol](docs/protocol.md): the contract between the app and the server
- [Releasing](docs/releasing.md): how a version is published
- [Server](apps/server/README.md): configuration, tuning, and tools
- [Desktop](apps/desktop/README.md): permissions, settings, and signing
