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

After `stop` the server ignores further audio, completes the transcript, refines it, and sends `done`. `stop` can come before `ready`: the audio sent so far waits for transcription to be ready, and the dictation goes on from there.

To cancel instead, close the socket. Nothing more is sent.

Audio or `stop` before `start`, a second `start`, and any other text message end the dictation with a `bad_request` error.

## Server to client

All server messages are JSON text.

| Message                                                                        | Meaning                                                                                 |
| ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| `{ "type": "ready" }`                                                          | Transcription is running.                                                               |
| `{ "type": "delta", "text": " plan is" }`                                      | More text, heard while the speaker talks. Append it to the text so far.                 |
| `{ "type": "done", "text": "So the plan is simple.", "usage": { … } }`         | The text of the dictation, to be typed, and what it used. The server closes the socket. |
| `{ "type": "error", "code": "timeout", "message": "Transcription timed out" }` | The dictation failed. The server closes the socket.                                     |

### Text

- The `delta` messages, appended in order, are the text heard so far. It is a draft to show, not to type: it has no leading whitespace, and it keeps arriving for a moment after `stop`.
- `done` carries the whole text of the dictation once, refined. It replaces the draft and has no leading or trailing whitespace. It is empty when nothing was said.
- When the refinement fails, `done` carries the transcript as it was heard. A dictation that reaches `done` never loses what was said.
- Exactly one of `done` and `error` ends a dictation, and nothing follows it.

### Usage

`done` says what the dictation used, and what that costs:

```json
{ "audio_seconds": 12.4, "input_tokens": 262, "output_tokens": 41, "cost": 0.00356 }
```

| Field           | Meaning                                                                                  |
| --------------- | ---------------------------------------------------------------------------------------- |
| `audio_seconds` | Seconds of audio that were transcribed                                                   |
| `input_tokens`  | Tokens the refinement read: the server's instructions, the speaker's, and the transcript |
| `output_tokens` | Tokens the refinement wrote                                                              |
| `cost`          | The cost in US dollars                                                                   |

The cost is an estimate. OpenAI reports the tokens but not the price, so the server works it out from the prices in its [configuration](../apps/server/README.md#configuration): the audio by the minute, the tokens by the million. When the refinement fails, its tokens are zero and the cost is that of the audio. A dictation that ends with an `error` reports no usage.

### Errors

| Code                   | Meaning                                                                                                                          |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `bad_request`          | The client sent a message that is not part of the protocol, or out of order.                                                     |
| `transcription_failed` | The transcription provider failed or disconnected.                                                                               |
| `timeout`              | Transcription was not ready within 10 s of `start`. Or nothing was heard, and the transcriber sent nothing for 5 s after `stop`. |

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
  │ ◀── done "So the plan is simple. We ship on Friday." + usage
  │ ◀──────────────────────────── close ─ │
```
