# Architecture

Voice turns speech into typed text: the words appear as they are heard, and the text is typed once, cleaned up, when the speaker stops. This page explains how.

```
 desktop app                         server                            OpenAI
┌────────────────┐  PCM audio   ┌──────────────────────┐  audio    ┌──────────────────────┐
│ microphone     │ ───────────▶ │ transcriber          │ ────────▶ │ realtime             │
│                │              │   one turn           │           │ transcription        │
│ pill           │ ◀─────────── │ session              │ ◀──────── │ (gpt-live-transcribe)│
│                │  delta       │   runs the dictation │  text     └──────────────────────┘
│ focused field  │ ◀─────────── │ refiner              │ ────────▶ ┌──────────────────────┐
└────────────────┘  done        │   one request        │ ◀──────── │ language model       │
                                └──────────────────────┘           │ (Responses API)      │
                                                                   └──────────────────────┘
```

The app owns the machine: the shortcuts, the microphone, the pill, typing, the history of what was dictated, which it keeps on the Mac with the recording of each dictation, and the statistics of how much was dictated and what it cost. The server owns the speech pipeline and the OpenAI key. They talk over one WebSocket per dictation, described in [the protocol](protocol.md).

## A dictation

A dictation has two phases, and its text has two states.

1. **While the speaker talks**, the audio is transcribed live. The text heard so far is a **draft**: the pill can show it, dimmed, and nothing is typed.
2. **When the speaker stops**, the transcript is completed and a language model refines all of it in one request. The **refined** text is typed into the focused field, once.

Typing once, at the end, is what keeps the text consistent. A sentence can only be written well when what follows it is known: where it ends, whether the speaker corrects it, how it connects to the next one. Text typed into another app also cannot be taken back reliably, so nothing is typed before it is final.

The price is that the text appears after the speaker stops, not during the speech. That wait is the transcript, about 0.7 s, plus the refinement, which grows with the length of the dictation: between 1 and 2 s for half a minute of speech.

## Transcription

The [transcriber](../apps/server/src/transcriber.ts) streams all the audio to an OpenAI realtime transcription session as **one turn**, and commits it once, when the speaker stops.

`gpt-live-transcribe` writes text while it listens, a little behind the voice, and that text only grows. Because the whole dictation is one turn, the model hears each sentence together with what comes next. It punctuates across pauses, and it recognizes words better than it does on audio cut into pieces: a pause in the middle of a sentence does not end the sentence.

After the commit the model returns the complete transcript. If the model goes silent for 5 s before it comes, the text heard so far stands in for it.

Recording never waits for a connection. The app records from the moment the shortcut is pressed and sends the audio as it comes. Audio that arrives before the transcription session is ready waits for it, and a speaker who stops before then is waited for too: the audio is transcribed once the session is ready, up to 10 s after the start.

## Refinement

The [refiner](../apps/server/src/refiner.ts) sends the complete transcript to a language model in a single request, with the instructions to follow: remove fillers and false starts, apply the speaker's own corrections, fix misheard words and punctuation, and change nothing else.

- **One request.** The model sees the whole text, so the result reads as one piece. Nothing is refined in parts that must be joined afterwards.
- **The speaker's instructions.** The app can send instructions with the dictation, such as a tone or a language. They are added after the server's own and take precedence over them.
- **Over a WebSocket.** The request goes through the Responses API on a WebSocket that the server opens when the dictation starts. When the speaker stops, the connection is already there, and the answer streams back on it.
- **It cannot lose text.** If the model fails, stops answering for 5 s, takes more than a minute, or returns nothing, the transcript is typed as it was heard.

## Cost

A dictation is charged twice by OpenAI: the transcription by the minute of audio, and the refinement by the token. The refinement reports the tokens it read and wrote. Nothing reports a price, so the server holds the prices in its configuration and sends an estimate of the cost with the text.

The app adds up what each dictation used, day by day, and shows it on its Statistics page with how much was dictated and how fast. Those figures are counted as dictations happen and kept apart from the history, so they stay when a transcription is deleted.

## Failure

- A transcription failure ends the dictation with an error. The app types the draft it has, so what was said is not lost, and shows the failure.
- A transcription session that is not ready within 10 s of the start ends the dictation with a timeout. So does a dictation that hears nothing and gets no transcript within 5 s of the stop.
- Cancelling types nothing.
- A dictation that fails is kept in the app's history with its recording. The app can send that recording again, as a new dictation, at once instead of at the pace it was spoken.
- The app shows a failure in the pill for three seconds: no microphone access, no microphone, server unreachable, or transcription failed.

## Why these choices

- **Native Swift app.** The product depends on a system-wide shortcut on a single modifier key, a window that floats over every app without taking focus, and typing into other apps. These are native macOS APIs.
- **A separate server.** The OpenAI key and the pipeline stay out of the app, so the pipeline can change without shipping the app, and the same server can run on another machine.
- **The server owns the text.** The app shows what the server sends and types what `done` carries. It does not assemble or correct text itself.
- **One refinement at the end.** Refining pieces while the speaker talks types text sooner, but each piece is written without knowing what follows, and the pieces do not read as one text. One request over the whole transcript trades that speed for a coherent result.
