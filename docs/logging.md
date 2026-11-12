# Logging

Every part of Voice logs the same way: the server, the development scripts, and the desktop app. A record says one thing that happened, in a form that reads well in a terminal and parses well by a machine.

## A record

| Part      | Meaning                                                                |
| --------- | ---------------------------------------------------------------------- |
| `time`    | When it happened                                                       |
| `level`   | `debug`, `info`, `warn`, or `error`                                    |
| `scope`   | The component the record is about, such as `server` or `dictation`     |
| `message` | What happened, as a short lowercase phrase                             |
| fields    | Everything that varies: identifiers, counts, durations, reasons, hints |

Write the message so that it is the same every time the event happens, and put the rest in fields. `refined` with `refine_ms=1180 chars=298`, not `refined 298 characters in 1180ms`.

Conventions for fields:

- Durations are in milliseconds and end in `_ms`.
- `error` holds the message of a failure that was caught.
- `hint` says what to do about a problem.
- Dictated text is never logged, only its length.

Levels:

| Level   | Use                                                                     |
| ------- | ----------------------------------------------------------------------- |
| `debug` | Detail for diagnosing one dictation. Hidden by default                  |
| `info`  | Something that normally happens: started, listening, refined, finished  |
| `warn`  | Something went wrong and was handled, such as a refinement falling back |
| `error` | Something failed: a dictation ended early, or the process cannot run    |

## Formats

In a terminal, records are printed for people, in columns and in color:

```
16:22:47.485 INFO  build       built app="build/Voice (Development).app" identifier=eu.cekrause.voice.dev duration_ms=1829
16:22:47.908 INFO  app         launched version=0.0.0 build=development
16:24:10.120 INFO  dictation   started dictation=1 instructions_chars=0
16:24:21.642 INFO  dictation   refined dictation=1 refine_ms=1180 chars=298
16:24:40.007 WARN  dictation   refinement failed dictation=2 refine_ms=5003 error="Refinement stalled"
16:24:20.310 ERROR server      OPENAI_API_KEY is not set hint="add your key to apps/server/.env"
```

Anywhere else, such as a pipe, a file, or a service manager, each record is one JSON object per line:

```json
{
  "time": "2026-11-11T16:24:21.642Z",
  "level": "info",
  "scope": "dictation",
  "message": "refined",
  "dictation": 1,
  "refine_ms": 1180,
  "chars": 298
}
```

Two environment variables override the defaults:

| Variable     | Values                           | Default                             |
| ------------ | -------------------------------- | ----------------------------------- |
| `LOG_FORMAT` | `pretty`, `json`                 | `pretty` in a terminal, else `json` |
| `LOG_LEVEL`  | `debug`, `info`, `warn`, `error` | `info`                              |

Color follows the terminal, and `NO_COLOR` turns it off.

## Where records come from

**The server and the scripts** use [`@voice/log`](../packages/log/src/index.ts):

```ts
import { createLogger } from "@voice/log";

const log = createLogger({ scope: "server" });
log.info("listening", { url });

// A logger for one dictation: another scope, and a field on every record.
const dictation = log.child({ scope: "dictation", fields: { dictation: 7 } });
dictation.warn("refinement failed", { refine_ms: 5003, error: "Refinement stalled" });
```

**The desktop app** writes to the macOS system log with [`Log`](../apps/desktop/Sources/Voice/Log.swift). The scope is the log category, and the message carries the fields as `key=value`:

```swift
private let log = Log("dictation")
log.info("started", ["mode": mode])
```

`pnpm dev` reads the app's records back from the system log and prints them like all the others. For an installed app, read them in Console, or with:

```sh
log stream --level debug --predicate 'subsystem == "eu.cekrause.voice"'
```

The development build uses the subsystem `eu.cekrause.voice.dev`.

**The server the production app runs** writes its records as JSON to `~/Library/Logs/eu.cekrause.voice/server.log`, which Console also shows.

## Scopes

| Scope         | Where   | What it reports                                                        |
| ------------- | ------- | ---------------------------------------------------------------------- |
| `env`         | server  | Changes to `apps/server/.env` made by `pnpm dev`                       |
| `server`      | server  | Startup, the address it listens on, and why it cannot start            |
| `dictation`   | server  | Each dictation: started, its timings, ended                            |
| `build`       | desktop | Compiling and signing the app                                          |
| `desktop`     | desktop | The development script: running and quitting the app                   |
| `reset`       | desktop | Forgetting the app's permissions and settings                          |
| `app`         | app     | Launch, the setup window, the shortcuts                                |
| `permissions` | app     | The state of the permissions, and each change                          |
| `setup`       | app     | The step the setup is on                                               |
| `dictation`   | app     | Each dictation: started, finished, cancelled, failed                   |
| `history`     | app     | Loading, saving, and pruning the past transcriptions, never their text |
| `retry`       | app     | Transcribing a failed dictation again                                  |
| `statistics`  | app     | Loading and saving the figures of what was dictated                    |
| `login`       | app     | Turning opening at login on and off                                    |
