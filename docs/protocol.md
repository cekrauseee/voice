# Protocol

The contract between the desktop app and the server. The server side is [`protocol.ts`](../apps/server/src/protocol.ts), the app side is [`ServerMessage.swift`](../apps/desktop/Sources/VoiceCore/ServerMessage.swift).

## Connection

One WebSocket is one dictation.

```
ws://<host>:<port>/v1/dictation
```

The client opens the socket when recording starts, sends `start`, and may send audio at once: the server buffers it until transcription is ready. Either side ends the dictation by closing the socket.

`GET /health` on the same host returns `{"status":"ok"}`.

The server answers WebSocket pings. A client can ping as it opens the socket to learn that the server is there, before `ready`.

## Client to server

### `start`

A text message, and the first message of the dictation.

```json
{
  "type": "start",
  "instructions": "Write in a formal tone.",
  "translate_to": "Spanish",
  "vocabulary": ["Claude", "Supabase"],
  "context": "Hi Ana,\n\nThanks for the update",
  "live": false
}
```

`instructions` says how the speaker wants the text written. The server adds it to its own instructions for the translation if one is requested, or for the rewrite otherwise. It takes precedence over the server's instructions. It is optional: without it, or when it is empty, the server refines its default way.

`translate_to` is the language to write the text in, as the speaker typed it, such as `Spanish` or `Brazilian Portuguese`. The refinement then translates what was said, by meaning and not word for word. It is optional: without it, or when it is empty, the text stays in the language spoken.

`vocabulary` is the speaker's dictionary: names and terms they use, spelled the way they write them. The transcription listens for them, the rewrite writes a word that was misheard as one of them as the term, where the context fits, and a translation keeps them as written. It is optional. The server puts each term on one line, takes out `<` and `>`, and leaves out blanks, terms longer than 100 characters, and terms already listed in another case. It passes on the first 500.

`context` is the text before the cursor in the field the dictation goes into, as the app read it: the end of it, up to about 2000 characters. The refinement uses it to spell names and terms the same way, match its register, and continue a sentence it leaves unfinished. It is never part of the text: the model does not rewrite or repeat it, nor follow instructions in it. It also decides whether `done` begins with a space. It is optional: without it, or when it is empty, the dictation is written on its own. The transcription does not get it.

`live` says whether the audio is transcribed while the speaker talks. With `true`, the server sends `delta` messages as it hears the words. Without it, or with `false`, the audio is transcribed once the speaker stops, and no `delta` comes: the first text is `done`. Both get the same hints from `vocabulary`.

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
| `{ "type": "ready" }`                                                          | Transcription is running. Without `live`, it comes at once.                             |
| `{ "type": "delta", "text": " plan is" }`                                      | More text, heard while the speaker talks. Append it to the text so far. Only `live`.    |
| `{ "type": "done", "text": "So the plan is simple.", "usage": { … } }`         | The text of the dictation, to be typed, and what it used. The server closes the socket. |
| `{ "type": "error", "code": "timeout", "message": "Transcription timed out" }` | The dictation failed. The server closes the socket.                                     |

### Text

- The `delta` messages, appended in order, are the text heard so far. They only come when `start` asked for `live` transcription. It is a draft to show, not to type: it has no leading whitespace, and it keeps arriving for a moment after `stop`.
- `done` carries the whole text of the dictation once, refined. It replaces the draft and has no trailing whitespace. It is empty when nothing was said.
- `done` has no leading whitespace either, unless it follows a `context` and needs a space to be separated from it: then it begins with one space. That is when the context ends in a word or in punctuation such as `.` or `,`, and the text does not begin with punctuation that attaches to what is before it, such as `,` or `)`. A context that ends in whitespace, in an opening bracket or quote, or in a language written without spaces, such as Chinese or Japanese, gets none. Type the text as it is, space included.
- When the refinement fails, `done` carries the transcript as it was heard, with the same space before it. A dictation that reaches `done` never loses what was said.
- Exactly one of `done` and `error` ends a dictation, and nothing follows it.

### Usage

`done` says what the dictation used, and what that costs:

```json
{ "audio_seconds": 12.4, "input_tokens": 262, "output_tokens": 41, "cost": 0.00356 }
```

| Field           | Meaning                                                                                |
| --------------- | -------------------------------------------------------------------------------------- |
| `audio_seconds` | Seconds of audio that were transcribed                                                 |
| `input_tokens`  | Tokens the refinement read, including instructions and text from both requests if used |
| `output_tokens` | Tokens the refinement wrote                                                            |
| `cost`          | The cost in US dollars                                                                 |

The cost is an estimate. OpenAI reports the tokens but not the price, so the server works it out from the prices in its [configuration](../apps/server/README.md#configuration): the audio by the minute, the tokens by the million. When refinement fails, usage still includes the tokens reported by any completed request. If the rewrite fails, the cost is that of the audio alone. A dictation that ends with an `error` reports no usage.

### Errors

| Code                   | Meaning                                                                                                                                               |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bad_request`          | The client sent a message that is not part of the protocol, or out of order.                                                                          |
| `transcription_failed` | The transcription provider failed or disconnected.                                                                                                    |
| `unreachable`          | The server could not reach the transcription provider: its connection failed before anything was transcribed.                                         |
| `timeout`              | Transcription was not ready within 10 s of `start`. Or nothing was heard, and the transcriber sent nothing for 5 s after `stop`, 60 s without `live`. |

An error ends the dictation without a `done`. The client still has the draft from the `delta` messages, if any came.

Without `live`, the server keeps the audio and transcribes nothing before `stop`, so `transcription_failed`, `unreachable`, and `timeout` come only after it: the server has tried the whole recording. With `live`, they can come at any moment, and the server may not have had all of it.

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
