# Server

Transcribes and refines dictation. The desktop app streams microphone audio over a WebSocket, and the server answers with text: see [the protocol](../../docs/protocol.md) and [the architecture](../../docs/architecture.md).

## Running

```sh
pnpm dev     # prepares .env, then restarts on changes
pnpm start   # runs once
```

`pnpm dev` first creates `.env` from `.env.example`, or adds the variables your `.env` is missing. It never changes a value you set. Add your `OPENAI_API_KEY` to `.env`: the server restarts when the file is saved.

On start the server checks the key and both models with OpenAI, then prints the address it listens on:

```
16:24:02.118 INFO  server      listening url=ws://127.0.0.1:8787/v1/dictation transcribe=gpt-live-transcribe refine=gpt-6-luna
```

If something is missing it says what to fix:

```
16:24:02.118 ERROR server      OPENAI_API_KEY is not set hint="add your key to apps/server/.env"
```

TypeScript runs directly on Node.js. There is no build step.

## Configuration

Environment variables, read from `.env`. `pnpm start` also runs without the file, with the variables set in the environment.

| Variable               | Default                             | Meaning                                                                                                 |
| ---------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `OPENAI_API_KEY`       | required                            | The key used for transcription and refinement                                                           |
| `HOST`                 | `127.0.0.1`                         | The address to listen on                                                                                |
| `PORT`                 | `8787`                              | The port to listen on                                                                                   |
| `TRANSCRIBE_MODEL`     | `gpt-live-transcribe`               | The realtime transcription model                                                                        |
| `TRANSCRIBE_LANGUAGES` | none                                | Comma-separated ISO 639-1 codes of the languages spoken, such as `en,pt`. Naming them improves accuracy |
| `REFINE_MODEL`         | `gpt-6-luna`                        | The model that refines each segment. It must support running without reasoning                          |
| `LOG_FORMAT`           | `pretty` in a terminal, else `json` | How log records are written: `pretty` or `json`                                                         |
| `LOG_LEVEL`            | `info`                              | The lowest level logged: `debug`, `info`, `warn`, or `error`                                            |

The server has no authentication and listens on the loopback address only. Do not set `HOST` to a public address without an authenticating proxy in front: anyone who can reach the server can spend your OpenAI credit.

## Logs

The server logs [structured records](../../docs/logging.md): in columns in a terminal, and as one JSON object per line anywhere else, which is what a service manager or a log collector sees.

```
16:24:10.120 INFO  dictation   started dictation=1
16:24:13.642 INFO  dictation   segment refined dictation=1 segment=0 final_ms=101 refine_ms=302 chars=42
16:24:21.930 INFO  dictation   ended dictation=1 outcome=done segments=3 duration_ms=11810
```

Each dictation has a number, on every record about it. `final_ms` is the time from the end of a segment to its transcript, and `refine_ms` the time the refinement took. `outcome` is `done`, `cancelled`, or the error code sent to the app.

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
| `scripts/env.ts`     | Prepares `.env` for `pnpm dev`                                                        |
