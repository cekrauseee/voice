# Server

Transcribes and refines dictation. The desktop app streams microphone audio over a WebSocket, and the server answers with text: see [the protocol](../../docs/protocol.md) and [the architecture](../../docs/architecture.md).

## Running

```sh
pnpm dev     # prepares .env, then restarts on changes
pnpm start   # runs once
```

`pnpm dev` first creates `.env` from `.env.example`, or adds the variables your `.env` is missing. It never changes a value you set. Add your `OPENAI_API_KEY` to `.env`: the server restarts when the file is saved.

On start the server checks the key and both models with OpenAI, then prints the address it listens on. If OpenAI cannot be reached, as just after login, it warns and starts anyway:

```
16:24:02.118 INFO  server      listening url=ws://127.0.0.1:8787/v1/dictation transcribe=gpt-live-transcribe refine=gpt-6-luna
```

If something is missing it says what to fix:

```
16:24:02.118 ERROR server      OPENAI_API_KEY is not set hint="add your key to apps/server/.env"
```

TypeScript runs directly on Node.js. There is no build step. The production app carries the server as one bundled file and runs it: see [the desktop README](../desktop/README.md#the-server).

## Configuration

Environment variables, read from `.env`. `pnpm start` also runs without the file, with the variables set in the environment.

| Variable                          | Default                             | Meaning                                                                                                                                          |
| --------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `OPENAI_API_KEY`                  | required                            | The key used for transcription and refinement                                                                                                    |
| `HOST`                            | `127.0.0.1`                         | The address to listen on                                                                                                                         |
| `PORT`                            | `8787`                              | The port to listen on                                                                                                                            |
| `TRANSCRIBE_MODEL`                | `gpt-live-transcribe`               | The realtime transcription model                                                                                                                 |
| `TRANSCRIBE_LANGUAGES`            | none                                | Comma-separated ISO 639-1 codes of the languages spoken, such as `en,pt`. Naming them improves accuracy                                          |
| `REFINE_MODEL`                    | `gpt-6-luna`                        | The model that refines the transcript. It must support running without reasoning                                                                 |
| `TRANSCRIBE_PRICE_PER_MINUTE`     | `0.017`                             | What OpenAI charges for a minute of audio transcribed, in US dollars                                                                             |
| `REFINE_PRICE_PER_MILLION_INPUT`  | `0.10`                              | What OpenAI charges for a million tokens the refinement reads, in US dollars                                                                     |
| `REFINE_PRICE_PER_MILLION_OUTPUT` | `0.50`                              | What OpenAI charges for a million tokens the refinement writes, in US dollars                                                                    |
| `LOG_FORMAT`                      | `pretty` in a terminal, else `json` | How log records are written: `pretty` or `json`                                                                                                  |
| `LOG_LEVEL`                       | `info`                              | The lowest level logged: `debug`, `info`, `warn`, or `error`                                                                                     |
| `STOP_WITH_PARENT`                | none                                | `1` to stop when the program that started the server ends, as the app does. The server watches its standard input, which that program holds open |

The prices are what the server estimates the cost of a dictation with, for the app's statistics. OpenAI reports what a dictation used, not what it costs. The defaults are [OpenAI's prices](https://developers.openai.com/api/docs/pricing) for the default models in November 2026: set them when you change a model, or when the prices change.

The server has no authentication and listens on the loopback address only. Do not set `HOST` to a public address without an authenticating proxy in front: anyone who can reach the server can spend your OpenAI credit.

## Logs

The server logs [structured records](../../docs/logging.md): in columns in a terminal, and as one JSON object per line anywhere else, which is what a service manager or a log collector sees.

```
16:24:10.120 INFO  dictation   started dictation=1 instructions_chars=0
16:24:20.462 INFO  dictation   transcribed dictation=1 transcript_ms=684 chars=340
16:24:21.642 INFO  dictation   refined dictation=1 refine_ms=1180 chars=298
16:24:21.642 INFO  dictation   used dictation=1 audio_seconds=10.3 input_tokens=318 output_tokens=71 cost=0.002986
16:24:21.643 INFO  dictation   ended dictation=1 outcome=done duration_ms=11523
```

Each dictation has a number, on every record about it. `transcript_ms` is the time from the stop to the complete transcript, and `refine_ms` the time the refinement then took: together they are how long the speaker waits for the text. `instructions_chars` is the length of the speaker's own instructions. `used` is what the dictation took and the estimate of its cost in US dollars, as sent to the app. `outcome` is `done`, `cancelled`, or the error code sent to the app.

## Tuning

The behavior of the pipeline is set by constants in the source:

| What                                                 | Where                                                      |
| ---------------------------------------------------- | ---------------------------------------------------------- |
| What the refiner is told to do                       | `INSTRUCTIONS` in [`refiner.ts`](src/refiner.ts)           |
| How long the model may go silent during a refinement | `STALL_MS` in [`responses.ts`](src/responses.ts)           |
| Readiness, transcript, and refinement timeouts       | The constants at the top of [`session.ts`](src/session.ts) |

To measure a change, replay a recording against the running server. Every message is printed with the time it arrived, and the server logs how long the transcript and the refinement took.

```sh
afconvert -f WAVE -d LEI16@24000 -c 1 input.m4a recording.wav
pnpm dictate recording.wav
pnpm dictate recording.wav --instructions "Write in a formal tone."
```

```
   942ms  ready
  2005ms  delta  "so the"
  2116ms  delta  " plan is"
 14198ms  stop
 16012ms  done   "So the plan is simple. We ship on Friday."
```

`--instructions` sends the speaker's instructions, as the app does from its settings.

## Tests

```sh
pnpm test
```

The tests run the real server, session, transcriber, and refiner. The OpenAI API is replaced by a local stand-in that speaks the same wire format, so the tests need no key. They do not prove that OpenAI behaves as its documentation says: check that with `pnpm dictate` and a real key.

## Layout

| File                 | Responsibility                                                                       |
| -------------------- | ------------------------------------------------------------------------------------ |
| `src/main.ts`        | Reads the configuration, checks OpenAI, starts the server                            |
| `src/server.ts`      | HTTP and WebSocket endpoints. One connection is one session                          |
| `src/session.ts`     | One dictation: drives the transcriber and the refiner, and falls back when one fails |
| `src/transcriber.ts` | The OpenAI realtime transcription session                                            |
| `src/responses.ts`   | A request to the Responses API over a WebSocket                                      |
| `src/refiner.ts`     | The refinement prompt                                                                |
| `src/protocol.ts`    | The messages exchanged with the app                                                  |
| `scripts/dictate.ts` | Replays a recording against a running server                                         |
| `scripts/env.ts`     | Prepares `.env` for `pnpm dev`                                                       |
