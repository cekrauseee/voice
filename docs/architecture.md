# Architecture

Voice turns speech into typed text with the lowest delay it can, without giving up the quality of an edited sentence. This page explains how.

```
 desktop app                         server                            OpenAI
┌────────────────┐  PCM audio   ┌──────────────────────┐  audio    ┌──────────────────────┐
│ microphone     │ ───────────▶ │ segmenter            │ ────────▶ │ realtime             │
│                │              │   splits at pauses   │  commit   │ transcription        │
│ pill           │ ◀─────────── │ session              │ ◀──────── │ (gpt-live-transcribe)│
│                │  delta/final │   orders the results │  text     └──────────────────────┘
│ focused field  │ ◀─────────── │ refiner              │ ────────▶ ┌──────────────────────┐
└────────────────┘  refined     └──────────────────────┘ ◀──────── │ language model       │
                                                                   └──────────────────────┘
```

The app owns the machine: the shortcuts, the microphone, the pill, and typing. The server owns the speech pipeline and the OpenAI key. They talk over one WebSocket per dictation, described in [the protocol](protocol.md).

## Segments

A dictation is cut into **segments**, roughly one per sentence. A segment is the unit of everything that follows: it is transcribed, completed, refined, and typed on its own.

Each segment goes through three states:

1. **Live.** The transcription model emits text while the speaker is still talking. This text is a draft and is only shown, never typed.
2. **Final.** When the segment ends, the model returns its complete transcript, which replaces the draft.
3. **Refined.** A language model rewrites the transcript: punctuation, capitalization, misheard words, fillers, false starts. Refined text is typed into the focused field and never changes again.

Working per segment is what keeps the delay low. Refining segment 3 runs while segment 4 is being transcribed, so the speaker never waits for a pass over the whole text: each sentence is typed as soon as it is refined.

It also means typed text is never rewritten. Replacing text in another app's field is unreliable: it breaks when the cursor moves and is not supported everywhere. So the app types a segment once, when it is final.

## Where a segment ends

`gpt-live-transcribe` has no turn detection: the caller decides when to commit the audio. The [segmenter](../apps/server/src/segmenter.ts) makes that decision from the audio level:

- A segment **opens** after 60 ms of speech. The 300 ms before it are kept, so the first word is not clipped.
- It **ends** at a pause of 600 ms, which is usually the end of a sentence or clause.
- Past 12 s it ends at the next pause of 200 ms, and past 20 s it ends anyway, so a speaker who does not pause still sees text.
- Audio between segments is silence and is not sent to OpenAI.

Speech is told from silence by comparing each 20 ms frame with a noise floor that follows the room.

The pause length is the main trade-off. A shorter pause types text sooner but cuts sentences into fragments, which refine worse. The values are constants in the segmenter, and `pnpm dictate` in the server replays a recording to measure the effect of changing them.

## Refinement

The [refiner](../apps/server/src/refiner.ts) sees one segment and the end of the refined text before it, about the last few segments. That text is context only: it is already typed.

A pause can fall in the middle of a sentence, so a segment is not always a sentence. Because the text before it cannot change, the refiner is told how to join them: start with a lowercase letter when the segment continues a sentence, and leave out the closing punctuation when it stops mid-sentence. The app puts one space between segments.

Refinement can only improve a segment, never lose it. If the model fails, takes more than 5 s, or returns something far longer than the transcript (it answered instead of cleaning up), the transcript is typed as is.

## The refinement queue

Segments are refined one at a time, in the order they were spoken. Each refinement depends on the one before: how a segment starts depends on how the refined text before it ended. So a segment waits in a queue until the segment before it is refined, and the [session](../apps/server/src/session.ts) sends each `refined` message as soon as it is ready, already in order.

Only refinement is queued. Transcription never waits: while a segment is being refined, the next ones are being recorded and transcribed. A refinement in progress is never cancelled when new speech arrives, because under continuous speech that would keep putting off the first text.

OpenAI does not guarantee the order of completed transcripts. When a later transcript arrives first, it waits for the earlier one.

## Failure

- A transcription failure ends the dictation with an error. Text already typed stays.
- After the speaker stops, the pipeline has 15 s to drain, then the dictation ends with a timeout.
- The app shows a failure in the pill for three seconds: no microphone access, no microphone, server unreachable, or transcription failed.

## Why these choices

- **Native Swift app.** The product depends on a system-wide shortcut on a single modifier key, a window that floats over every app without taking focus, and typing into other apps. These are native macOS APIs.
- **A separate server.** The OpenAI key and the pipeline stay out of the app, so the pipeline can change without shipping the app, and the same server can run on another machine.
- **Commit on the server.** The server sees the whole stream and owns the provider session, so the commit policy lives beside the code it drives. The app just streams audio.
