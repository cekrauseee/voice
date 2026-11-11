# Server

Transcribes and refines dictation. The desktop app streams microphone audio over a WebSocket, and the server answers with text: see [the protocol](../../docs/protocol.md) and [the architecture](../../docs/architecture.md).

## Running

```sh
cp .env.example .env   # then add your OPENAI_API_KEY
pnpm dev               # restarts on changes
pnpm start             # runs once
```

On start the server checks the key and both models with OpenAI, then prints the address it listens on:

```
ready: ws://127.0.0.1:8787/v1/dictation
```

If something is missing it exits and says what to fix, for example `error: OPENAI_API_KEY is not set.`

TypeScript runs directly on Node.js. There is no build step.

## Configuration

Environment variables, read from `.env` when present.

| Variable               | Default               | Meaning                                                                                                 |
| ---------------------- | --------------------- | ------------------------------------------------------------------------------------------------------- |
| `OPENAI_API_KEY`       | required              | The key used for transcription and refinement                                                           |
| `HOST`                 | `127.0.0.1`           | The address to listen on                                                                                |
| `PORT`                 | `8787`                | The port to listen on                                                                                   |
| `TRANSCRIBE_MODEL`     | `gpt-live-transcribe` | The realtime transcription model                                                                        |
| `TRANSCRIBE_LANGUAGES` | none                  | Comma-separated ISO 639-1 codes of the languages spoken, such as `en,pt`. Naming them improves accuracy |
| `REFINE_MODEL`         | `gpt-6-luna`          | The model that refines each segment. It must support running without reasoning                          |

The server has no authentication and listens on the loopback address only. Do not set `HOST` to a public address without an authenticating proxy in front: anyone who can reach the server can spend your OpenAI credit.

## Tuning

The behavior of the pipeline is set by constants in the source:

| What                                            | Where                                                           |
| ----------------------------------------------- | --------------------------------------------------------------- |
| When a segment starts and ends                  | `defaultSegmenterOptions` in [`segmenter.ts`](src/segmenter.ts) |
| How speech is told from silence                 | The constants at the top of [`segmenter.ts`](src/segmenter.ts)  |
| What the refiner is told to do                  | `INSTRUCTIONS` in [`refiner.ts`](src/refiner.ts)                |
| Refinement timeout, drain timeout, context size | The constants at the top of [`session.ts`](src/session.ts)      |

To measure a change, replay a recording against the running server. Every message is printed with the time it arrived, and the server logs how long each segment took to complete and to refine.

```sh
afconvert -f WAVE -d LEI16@24000 -c 1 input.m4a recording.wav
pnpm dictate recording.wav
```

```
    54ms  ready
  2310ms  delta   0  "so the plan"
  5387ms  final   0  "so the plan is simple"
  5690ms  refined 0  "So the plan is simple."
 14198ms  stop
 14602ms  done
```

## Tests

```sh
pnpm test
```

The tests run the real server, session, and segmenter. The OpenAI API is replaced by a local stand-in that speaks the same wire format, so the tests need no key. They do not prove that OpenAI behaves as its documentation says: check that with `pnpm dictate` and a real key.

## Layout

| File                 | Responsibility                                                                        |
| -------------------- | ------------------------------------------------------------------------------------- |
| `src/main.ts`        | Reads the configuration, checks OpenAI, starts the server                             |
| `src/server.ts`      | HTTP and WebSocket endpoints. One connection is one session                           |
| `src/session.ts`     | One dictation: drives the segmenter, transcriber, and refiner, and orders the results |
| `src/segmenter.ts`   | Splits the audio into segments                                                        |
| `src/transcriber.ts` | The OpenAI realtime transcription session                                             |
| `src/refiner.ts`     | The refinement prompt and request                                                     |
| `src/protocol.ts`    | The messages exchanged with the app                                                   |
| `scripts/dictate.ts` | Replays a recording against a running server                                          |
