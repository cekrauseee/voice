# Protocol

The contract between the desktop app and the server. The server side is [`protocol.ts`](../apps/server/src/protocol.ts), the app side is [`ServerMessage.swift`](../apps/desktop/Sources/VoiceCore/ServerMessage.swift) and [`MeetingMessage.swift`](../apps/desktop/Sources/VoiceCore/MeetingMessage.swift).

There are two kinds of connection: a [dictation](#dictation), which types one text, and a [meeting](#meeting), which transcribes a conversation for as long as it lasts. `GET /health` on the same host returns `{"status":"ok"}`.

# Dictation

## Connection

One WebSocket is one dictation.

```
ws://<host>:<port>/v1/dictation
```

The client opens the socket when recording starts, sends `start`, and may send audio at once: the server buffers it until transcription is ready. Either side ends the dictation by closing the socket.

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

# Meeting

## Connection

One WebSocket is one connection of a meeting. A meeting can take several, one after the other: the client keeps the transcript, and when a connection drops it opens another and tells the server where to go on from.

```
ws://<host>:<port>/v1/meeting
```

A meeting has two channels of audio, each a side of the conversation:

| Channel  | Frame byte | What it carries                                            |
| -------- | ---------- | ---------------------------------------------------------- |
| `me`     | `0`        | The speaker, through the microphone                        |
| `others` | `1`        | The other participants, through what the meeting app plays |

Each channel has a clock, in seconds since the meeting started, that advances with the audio the client sends on it. The two channels are expected to be aligned: the client sends silence where one started later than the other.

## Client to server

### `start`

A text message, and the first message of the connection.

```json
{ "type": "start", "instructions": "", "first_id": 1, "offsets": { "me": 0, "others": 0 } }
```

| Field          | Meaning                                                                                                                                                                                 |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `instructions` | How the speaker wants the text written, for the revision of the transcript. Optional                                                                                                    |
| `first_id`     | The id of the first segment the server sends. Optional, `1` by default                                                                                                                  |
| `offsets`      | Where each channel's clock starts, in seconds. Optional, `0` by default. On a connection that picks a meeting up, the end of the last segment the client got on the channel, or earlier |

### Audio

Binary messages carry audio: one byte that names the channel, then 16-bit little-endian mono PCM at 24 kHz. The app sends 40 ms per message, per channel. The server cuts each channel into stretches of speech itself, so it needs the silence too: the client sends the channel's audio whole.

### `stop`

A text message. The meeting is over.

```json
{ "type": "stop" }
```

After `stop` the server ignores further audio, completes the stretches of speech that are open, sends their segments, and sends `done`.

To leave a connection without ending the meeting, close the socket. Nothing more is sent, and the server keeps nothing: the client picks the meeting up on another connection.

Audio or `stop` before `start`, a second `start`, a frame that names no channel, and any other text message end the connection with a `bad_request` error.

## Server to client

All server messages are JSON text.

| Message                                                                                        | Meaning                                                                                                     |
| ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `{ "type": "ready" }`                                                                          | Both channels are being transcribed.                                                                        |
| `{ "type": "draft", "channel": "me", "text": "so the plan" }`                                  | The text heard on a channel that is not in a segment yet. It replaces the channel's draft, and may be empty |
| `{ "type": "segment", "id": 7, "channel": "others", "start": 12.4, "end": 15.1, "text": "…" }` | A stretch of speech on a channel, with its text: see below                                                  |
| `{ "type": "revised", "from": 4, "to": 9, "segments": [ … ] }`                                 | The segments with ids from `from` to `to`, revised: `segments` replace them. See below                      |
| `{ "type": "usage", "usage": { … } }`                                                          | What the connection has used so far. Sent after each segment and each revision                              |
| `{ "type": "done", "usage": { … } }`                                                           | The meeting is over and every segment was sent. The server closes the socket.                               |
| `{ "type": "error", "code": "timeout", "message": "Transcription timed out" }`                 | The connection failed. The server closes the socket. The client may open another                            |

### Segments

A segment is a stretch of speech on one channel, cut at a pause, with the text the transcription model gave it. `start` and `end` are seconds of the channel's clock. Segments of a channel come in the order they were spoken, and never overlap; the segments of the two channels interleave as the conversation did. Ids count up from `first_id`, in the order the segments were sent, across both channels.

The text of a segment is the model's complete transcript of the stretch. When that transcript does not come in time, the text heard stands in. A stretch in which nothing was heard makes no segment.

A `draft` is the text heard on a channel that is not in a segment yet: the stretch being spoken, and the ones before it whose transcript is still on its way. It is a draft to show, not to keep. After a connection that was lost, the server may start a stretch over, and the draft starts over with it.

### Revisions

As the meeting goes, the server revises the transcript in windows of a few minutes: a language model fixes punctuation and misheard words, removes fillers, and joins or splits the stretches where the pauses cut them wrong, with the window before as context. A `revised` message carries the result: the segments with ids from `from` to `to` are replaced by its `segments`, which have new ids, after every id sent so far, and the times of the stretches they came from. A revised segment may be on the other channel than the stretch it came from, when the model found it belonged to the other side.

The ids in a window are those of the segments sent between two points, so they are contiguous. The window closes once it spans two minutes and some 150 words, before a segment that comes after a pause, or at four minutes regardless. The stop closes the last one, and `done` comes after its revision. A window the model cannot revise keeps its text, and no message says so. Revisions do not cross connections: what was sent on a connection that was lost before its window closed stays as heard.

`instructions` from `start` go to the model, after the server's own, and take precedence over them.

### Usage

`usage` and `done` carry what the connection used, in the form a dictation's `done` [does](#usage). `audio_seconds` is the speech sent to be transcribed: the silence between stretches is not sent, and not paid for. The tokens are those of the revisions. The figures are those of the connection: a client that comes back on another adds them up.

### Errors

| Code                   | Meaning                                                                      |
| ---------------------- | ---------------------------------------------------------------------------- |
| `bad_request`          | The client sent a message that is not part of the protocol, or out of order. |
| `transcription_failed` | The transcription provider failed repeatedly on a channel.                   |
| `timeout`              | Transcription was not ready within 10 s of `start`.                          |

An error ends the connection, not the meeting: the client keeps what it got and may open another connection, with `offsets` where its segments end.

## Example

```
client                                   server
  │ ── open /v1/meeting ────────────────▶ │
  │ ── start first_id=1 ────────────────▶ │
  │ ── [0] audio … ─────────────────────▶ │
  │ ── [1] audio … ─────────────────────▶ │
  │ ◀──────────────────────────── ready ─ │
  │ ◀── draft me "so the"                 │
  │ ◀── draft me "so the plan is"         │
  │ ◀── segment 1 me 0.0-2.3 "So the plan is simple."
  │ ◀── usage                             │
  │ ◀── draft me ""                       │
  │ ◀── draft others "sounds"             │
  │ ◀── segment 2 others 2.1-3.4 "Sounds good."
  │ ◀── usage                             │
  │ ── stop ────────────────────────────▶ │
  │ ◀── segment 3 me 3.5-5.0 "friday then"
  │ ◀── revised 1-3: 4 me 0.0-2.3 "So the plan is simple.", 5 others 2.1-3.4 "Sounds good.", 6 me 3.5-5.0 "Friday, then."
  │ ◀── usage                             │
  │ ◀── done + usage                      │
  │ ◀──────────────────────────── close ─ │
```
