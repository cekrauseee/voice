# Protocol

The contract between the desktop app and the server. The server side is [`protocol.ts`](../apps/server/src/protocol.ts), the app side is [`ServerMessage.swift`](../apps/desktop/Sources/VoiceCore/ServerMessage.swift).

## Connection

One WebSocket is one dictation.

```
ws://<host>:<port>/v1/dictation
```

The client opens the socket when recording starts, sends `start`, and may send audio at once: the server buffers it until transcription is ready. Either side ends the dictation by closing the socket.

`GET /health` on the same host returns `{"status":"ok"}`. `ws://<host>:<port>/v1/profile` is one turn of the conversation that writes the speaker's profile: see [The profile conversation](#the-profile-conversation).

The server refuses a WebSocket whose handshake has an `Origin` header, with `403`. Browsers send one, and the app does not: a web page cannot use the server through the loopback address.

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
  "live": false,
  "transcription_prompt": "A software developer speaking Brazilian Portuguese about Git, with English terms such as merge and rebase.",
  "languages": ["pt", "en"]
}
```

`instructions` says how the speaker wants the text written, and what the rewrite needs to know about them to tell a misheard term. The server adds it to its own instructions for the rewrite, and for the translation if one is requested. It takes precedence over the server's instructions. It is optional: without it, or when it is empty, the server refines its default way.

`translate_to` is the language to write the text in, as the speaker typed it, such as `Spanish` or `Brazilian Portuguese`. The refinement then translates what was said, by meaning and not word for word. It is optional: without it, or when it is empty, the text stays in the language spoken.

`vocabulary` is the speaker's dictionary: names and terms they use, spelled the way they write them. The transcription listens for them, the rewrite writes a word that was misheard as one of them as the term, where the context fits, and a translation keeps them as written. It is optional. The server puts each term on one line, takes out `<` and `>`, and leaves out blanks, terms longer than 100 characters, and terms already listed in another case. It passes on the first 500.

`context` is the text before the cursor in the field the dictation goes into, as the app read it: the end of it, up to about 2000 characters. The refinement uses it to spell names and terms the same way, match its register, and continue a sentence it leaves unfinished. It is never part of the text: the model does not rewrite or repeat it, nor follow instructions in it. It also decides whether `done` begins with a space. It is optional: without it, or when it is empty, the dictation is written on its own. The transcription does not get it.

`live` says whether the audio is transcribed while the speaker talks. With `true`, the server sends `delta` messages as it hears the words. Without it, or with `false`, the audio is transcribed once the speaker stops, and no `delta` comes: the first text is `done`. Both get the same hints: `vocabulary`, `transcription_prompt`, and `languages`.

`transcription_prompt` describes the speaker's recordings to the transcription: who speaks, in which languages, and about what. It is optional. The server makes it one paragraph, takes out control characters, and cuts it at a word to 1000 characters, for both models: the live model refuses a prompt longer than 1024, and the other one longer than 65536.

`languages` are the languages the speaker speaks, as ISO 639-1 codes, the one spoken most first. They take the place of the server's `TRANSCRIBE_LANGUAGES` for the dictation. It is optional: without it, or when it is empty, the server's are used, and without those the model tells the language itself. The server lowercases each code, drops a region (`pt-BR` is `pt`), leaves out what is not two letters and codes already listed, and passes on the first 10.

The instructions, the transcription prompt, and the languages are the speaker's profile, which the app keeps, and the agent writes in a conversation with the speaker: see [The profile conversation](#the-profile-conversation).

The transcription prompt, the languages, and the vocabulary are hints, and a hint never fails a dictation. When OpenAI refuses them, as it does a language code it does not know, the server transcribes again without them, with its own `TRANSCRIBE_LANGUAGES`, and logs a warning. A recording in parts is transcribed without them from the part refused on.

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

## The profile conversation

The speaker's profile is what the models are told about them: how they want their text written, what their recordings are like, and the languages they speak. An agent writes it in a conversation with them, by voice: it asks, they answer, and it updates the profile as it learns. The client keeps the profile, and sends it with each `start` of a dictation.

One WebSocket is one turn of the conversation: what the speaker says, and the agent's answer.

```
ws://<host>:<port>/v1/profile
```

The server keeps nothing between turns. The client holds the conversation, in memory, and sends it with each turn, with the profile as it is now.

### `start`

A text message, and the first message of the turn.

```json
{
  "type": "start",
  "history": [
    {
      "role": "assistant",
      "text": "Oi! Me conta sobre você: o que você faz e o que costuma ditar?"
    },
    { "role": "user", "text": "Sou desenvolvedor de software." },
    {
      "role": "assistant",
      "text": "Você costuma ditar em português, em inglês ou mistura os dois?",
      "profile": {
        "instructions": "A pessoa é desenvolvedora de software…",
        "transcription_prompt": "Desenvolvedor de software falando português.",
        "languages": ["pt"],
        "terms": []
      }
    }
  ],
  "profile": {
    "instructions": "A pessoa é desenvolvedora de software…",
    "transcription_prompt": "Desenvolvedor de software falando português.",
    "languages": ["pt"],
    "terms": []
  },
  "vocabulary": ["Claude"]
}
```

| Field        | Meaning                                                                                                                                                                                           |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `history`    | The conversation so far, oldest first. `user` is the speaker and `assistant` the agent. An agent message has the `profile` it wrote, when it changed it, so the agent can undo a change. Optional |
| `profile`    | The speaker's profile as it is now. `terms` are the terms suggested for their dictionary and not added yet. Optional: without it, the speaker has none                                            |
| `vocabulary` | The speaker's dictionary. Optional                                                                                                                                                                |

The client opens the conversation itself, with a question of its own, as the first `assistant` message: the agent is not asked for it.

Audio and `stop` follow, as in a dictation. What the speaker says is transcribed live, always, so their words can be shown as they speak, with the profile's transcription prompt and languages, and the dictionary, as hints. It is not rewritten: the agent reads the transcript as it is.

### To the client

| Message                                                                               | Meaning                                                                             |
| ------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `{ "type": "ready" }`                                                                 | Transcription is running.                                                           |
| `{ "type": "delta", "text": "sou des" }`                                              | More of what the speaker says, heard while they talk. Append it to the text so far. |
| `{ "type": "heard", "text": "Sou desenvolvedor." }`                                   | All of what the speaker said. It replaces the deltas. Empty when nothing was heard. |
| `{ "type": "reply", "text": "Entendi. " }`                                            | More of the agent's reply, as it is written. Append it to the reply so far.         |
| `{ "type": "done", "reply": "…", "profile": { … }, "add_terms": [], "usage": { … } }` | The agent's answer. The server closes the socket.                                   |
| `{ "type": "error", "code": "agent_failed", "message": "…" }`                         | The turn failed. The server closes the socket.                                      |

`done` carries the whole reply, which stands for the `reply` messages, and:

- `profile`: the whole profile, when the agent changed it, in the shape of `start`'s, or `null`. `transcription_prompt` is at most 1000 characters, `languages` are codes the transcription model takes, and `terms` are up to 15 terms suggested for the dictionary, without the ones in it. They are suggestions: the client adds only the ones the speaker accepts.
- `add_terms`: the terms the speaker asked the agent, in this turn, to add to their dictionary. Usually empty.
- `usage`: what the turn used, as for a dictation: the audio, and the tokens of the agent.

When nothing was heard, `heard` is empty, the agent is not asked, and `done` has an empty `reply` and no profile.

The errors are those of a dictation, and `agent_failed` when the agent failed, gave an answer that is not one, or took more than 30 s in all, or 5 s without a word. A failure changes nothing: the client keeps the profile it had.

```
client                                   server
  │ ── open /v1/profile ────────────────▶ │
  │ ── start (history, profile) ────────▶ │
  │ ── audio … ─────────────────────────▶ │
  │ ◀──────────────────────────── ready ─ │
  │ ◀── delta "falo português"            │
  │ ── stop ────────────────────────────▶ │
  │ ◀── heard "Falo português, com os termos de Git em inglês."
  │ ◀── reply "Vou manter os termos"      │
  │ ◀── reply " em inglês. Como você…"    │
  │ ◀── done reply + profile + usage      │
  │ ◀──────────────────────────── close ─ │
```
