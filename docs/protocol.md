# Protocol

The contract between the desktop app and the server. The server side is [`protocol.ts`](../apps/server/src/protocol.ts), the app side is [`ServerMessage.swift`](../apps/desktop/Sources/VoiceCore/ServerMessage.swift).

## Connection

One WebSocket is one dictation.

```
ws://<host>:<port>/v1/dictation
```

The client opens the socket when recording starts and may send audio at once: the server buffers it until transcription is ready. Either side ends the dictation by closing the socket.

`GET /health` on the same host returns `{"status":"ok"}`.

## Client to server

### Audio

Binary messages carry the microphone audio as 16-bit little-endian mono PCM at 24 kHz. Messages may be of any length. The app sends 40 ms per message.

### `stop`

A text message. The speaker is done.

```json
{ "type": "stop" }
```

After `stop` the server ignores further audio, finishes the segments in progress, and sends `done`.

To cancel instead, close the socket. Nothing more is sent.

Any other text message ends the dictation with a `bad_request` error.

## Server to client

All server messages are JSON text. A `segment` is a number counted from 0 in the order the segments were spoken.

| Message                                                                        | Meaning                                                                 |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| `{ "type": "ready" }`                                                          | Transcription is running.                                               |
| `{ "type": "delta", "segment": 0, "text": "hello" }`                           | More live text for a segment. Append it to what the segment has.        |
| `{ "type": "final", "segment": 0, "text": "hello world" }`                     | The complete transcript of a segment. It replaces the live text.        |
| `{ "type": "refined", "segment": 0, "text": "Hello, world." }`                 | The refined text of a segment, to be typed. It replaces the transcript. |
| `{ "type": "done" }`                                                           | Every segment is refined. The server closes the socket.                 |
| `{ "type": "error", "code": "timeout", "message": "Transcription timed out" }` | The dictation failed. The server closes the socket.                     |

### Ordering

- `refined` messages arrive in segment order, each segment exactly once. A client can type them as they arrive.
- `delta` and `final` messages of different segments can interleave, and a `final` can arrive for a later segment first.
- A segment's `refined` follows its `final`. No `delta` or `final` follows a segment's `refined`.
- `text` in `final` and `refined` has no leading or trailing whitespace, and can be empty when a segment held no words. The client separates the segments it types with one space.

### Errors

| Code                   | Meaning                                            |
| ---------------------- | -------------------------------------------------- |
| `bad_request`          | The client sent a text message other than `stop`.  |
| `transcription_failed` | The transcription provider failed or disconnected. |
| `timeout`              | The segments did not finish within 15 s of `stop`. |

An error ends the dictation. Segments already refined were delivered and stay valid.

## Example

```
client                                   server
  │ ── open /v1/dictation ──────────────▶ │
  │ ── audio … ─────────────────────────▶ │
  │ ◀──────────────────────────── ready ─ │
  │ ◀── delta 0 "so the"                  │
  │ ◀── delta 0 " plan is"                │
  │ ── audio … ─────────────────────────▶ │   (pause: segment 0 ends)
  │ ◀── final 0 "so the plan is simple"   │
  │ ◀── delta 1 "we ship"                 │
  │ ◀── refined 0 "So the plan is simple."│
  │ ── stop ────────────────────────────▶ │
  │ ◀── final 1 "we ship on friday"       │
  │ ◀── refined 1 "We ship on Friday."    │
  │ ◀───────────────────────────── done ─ │
  │ ◀──────────────────────────── close ─ │
```
