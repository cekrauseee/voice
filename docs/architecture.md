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
└────────────────┘  done        │   rewrite, then      │ ◀──────── │ language model       │
                                │   translate if asked │           │ (Responses API)      │
                                └──────────────────────┘           └──────────────────────┘
```

The app owns the machine: the shortcuts, the microphone, the pill, typing, the history of what was dictated, which it keeps on the Mac with the recording of each dictation, and the statistics of how much was dictated and what it cost. The server owns the speech pipeline and the OpenAI key. They talk over one WebSocket per dictation, described in [the protocol](protocol.md).

## A dictation

A dictation has two phases, and its text has two states.

1. **While the speaker talks**, the audio is transcribed live. The text heard so far is a **draft**: the pill can show it, dimmed, and nothing is typed.
2. **When the speaker stops**, the transcript is completed and a language model rewrites all of it, then translates it if asked. The **refined** text is typed into the focused field, once.

Typing once, at the end, is what keeps the text consistent. A sentence can only be written well when what follows it is known: where it ends, whether the speaker corrects it, how it connects to the next one. Text typed into another app also cannot be taken back reliably, so nothing is typed before it is final.

The price is that the text appears after the speaker stops, not during the speech. That wait is the transcript, about 0.7 s, plus the refinement, which grows with the length of the dictation. Rewriting half a minute of speech takes between 1 and 2 s. Translation adds the time of a second request.

## Transcription

The [transcriber](../apps/server/src/transcriber.ts) streams all the audio to an OpenAI realtime transcription session as **one turn**, and commits it once, when the speaker stops.

`gpt-live-transcribe` writes text while it listens, a little behind the voice, and that text only grows. Because the whole dictation is one turn, the model hears each sentence together with what comes next. It punctuates across pauses, and it recognizes words better than it does on audio cut into pieces: a pause in the middle of a sentence does not end the sentence.

The speaker's dictionary, the names and terms they use, goes to the session as keywords to listen for. They are hints: a word that only sounds like one can still be written as heard, and the refinement looks again.

After the commit the model returns the complete transcript. If the model goes silent for 5 s before it comes, the text heard so far stands in for it.

Recording never waits for a connection. The app records from the moment the shortcut is pressed and sends the audio as it comes. Audio that arrives before the transcription session is ready waits for it, and a speaker who stops before then is waited for too: the audio is transcribed once the session is ready, up to 10 s after the start.

## Refinement

The refiner sends the complete transcript to a language model to remove fillers and false starts, apply the speaker's own corrections, and fix misheard words and punctuation. [Refiner source](../apps/server/src/refiner.ts).

- **One rewrite.** The model sees the whole text, so the result reads as one piece.
- **The speaker's instructions.** The app can send instructions with the dictation, such as a tone. They are added to the translation request if there is one, or to the rewrite otherwise, and take precedence over the server's instructions.
- **The speaker's dictionary.** The app keeps a list of the speaker's names and terms, and sends it with each dictation. The rewrite is given it to tell what a misheard word was: a word that sounds like a term becomes the term where the context fits, such as "cloud" for "Claude" in a sentence about a model, and stays as it is where it means something else. The translation is told to keep the terms as written.
- **The text before the cursor.** When the dictation starts, the app reads the end of the text before the cursor in the focused field, through the Accessibility API, and sends it with the dictation. The model is given it apart from the transcript, in both requests, as context only: to spell names and terms the way the field does, match its register, and write a dictation that goes on with an unfinished sentence as the rest of it, without a capital letter. It never rewrites, repeats, or obeys that text. The server then puts a space before the result when it would otherwise run into the text before it, so the app types it as it comes. Reading the field is bounded to a few tens of milliseconds and happens once the microphone is opening, so recording never waits for it: an app that is busy or does not say gives no context. Password fields are never read, and the setting Use text in the field turns it off, since that text goes to OpenAI too. A failed dictation tried again from the history has no context: the field focused then is another, and its text is not typed. The transcription does not get the context: its prompt describes the setting of a recording, not the text it follows, and a prompt longer than the model's undocumented limit would fail the whole dictation.
- **Translation.** The app can ask for the text in another language. That takes a second request, after the first: the model is given the rewritten text, and told to write what the speaker meant the way a native writer would, with that language's own idioms and expressions, and not word for word. Asked to rewrite and translate at once, it follows the speaker's words too closely. The speaker waits for both requests, and both are counted in what the dictation cost.
- **Over a WebSocket.** The requests go through the Responses API on a WebSocket that the server opens when the dictation starts. When the speaker stops, the connection is already there, and the answers stream back on it.
- **It cannot lose text.** Refinement has 60 s in all. In each request, the model has 5 s to send its next event. If either limit is reached, the model fails, or a request returns nothing, the transcript is typed as it was heard, untranslated.

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
- **A separate server.** The OpenAI key and the pipeline stay out of the app, so the pipeline can change without shipping the app, and the same server can run on another machine. On one Mac, the production app carries the server and runs it while it runs, with the key from the server's own `.env`.
- **The server owns the text.** The app shows what the server sends and types what `done` carries. It does not assemble or correct text itself: even the space that separates a dictation from the text before the cursor comes from the server, which knows the language and the punctuation.
- **One refinement at the end.** Refining pieces while the speaker talks types text sooner, but each piece is written without knowing what follows, and the pieces do not read as one text. Rewriting the whole transcript together trades that speed for a coherent result.
