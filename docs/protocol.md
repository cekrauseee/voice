# Protocol

The contract between the desktop app and the server. The server side is [`protocol.ts`](../apps/server/src/protocol.ts), the app side is [`ServerMessage.swift`](../apps/desktop/Sources/VoiceCore/ServerMessage.swift).

## Connection

One WebSocket is one dictation.

```
ws://<host>:<port>/v1/dictation
```

The client opens the socket when recording starts, sends `start`, and may send audio at once: the server buffers it until transcription is ready. Either side ends the dictation by closing the socket.

`GET /health` on the same host returns `{"status":"ok"}`.

## Client to server

### `start`

A text message, and the first message of the dictation.

```json
{ "type": "start", "instructions": "Write in a formal tone." }
```

`instructions` says how the speaker wants the text written. The server adds it to its own instructions for the refinement, and it takes precedence over them. It is optional: without it, or when it is empty, the server refines its default way.

### Audio

Binary messages carry the microphone audio as 16-bit little-endian mono PCM at 24 kHz. Messages may be of any length. The app sends 40 ms per message.

### `stop`

A text message. The speaker is done.

```json
{ "type": "stop" }
```

After `stop` the server ignores further audio, completes the transcript, refines it, and sends `done`.

To cancel instead, close the socket. Nothing more is sent.

Audio or `stop` before `start`, a second `start`, and any other text message end the dictation with a `bad_request` error.

## Server to client

All server messages are JSON text.

| Message                                                                        | Meaning                                                                 |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| `{ "type": "ready" }`                                                          | Transcription is running.                                               |
| `{ "type": "delta", "text": " plan is" }`                                      | More text, heard while the speaker talks. Append it to the text so far. |
| `{ "type": "done", "text": "So the plan is simple." }`                         | The text of the dictation, to be typed. The server closes the socket.   |
| `{ "type": "error", "code": "timeout", "message": "Transcription timed out" }` | The dictation failed. The server closes the socket.                     |

### Text

- The `delta` messages, appended in order, are the text heard so far. It is a draft to show, not to type: it has no leading whitespace, and it keeps arriving for a moment after `stop`.
- `done` carries the whole text of the dictation once, refined. It replaces the draft and has no leading or trailing whitespace. It is empty when nothing was said.
- When the refinement fails, `done` carries the transcript as it was heard. A dictation that reaches `done` never loses what was said.
- Exactly one of `done` and `error` ends a dictation, and nothing follows it.

### Errors

| Code                   | Meaning                                                                      |
| ---------------------- | ---------------------------------------------------------------------------- |
| `bad_request`          | The client sent a message that is not part of the protocol, or out of order. |
| `transcription_failed` | The transcription provider failed or disconnected.                           |
| `timeout`              | Nothing was heard, and no transcript came within 5 s of `stop`.              |

An error ends the dictation without a `done`. The client still has the draft from the `delta` messages.

## Example

```
client                                   server
  │ ── open /v1/dictation ──────────────▶ │
  │ ── start ───────────────────────────▶ │
  │ ── audio … ─────────────────────────▶ │
  │ ◀──────────────────────────── ready ─ │
  │ ◀── delta "so the"                    │
  │ ◀── delta " plan is"                  │
  │ ── audio … ─────────────────────────▶ │
  │ ◀── delta " um simple"                │
  │ ── stop ────────────────────────────▶ │
  │ ◀── delta " we ship on friday"        │
  │ ◀── done "So the plan is simple. We ship on Friday."
  │ ◀──────────────────────────── close ─ │
```
