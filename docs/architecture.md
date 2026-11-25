# Architecture

Voice turns speech into typed text: the speaker talks, and the text is typed once, cleaned up, when they stop. This page explains how.

```
 desktop app                         server                            OpenAI
┌────────────────┐  PCM audio   ┌──────────────────────┐  audio    ┌──────────────────────┐
│ microphone     │ ───────────▶ │ transcriber          │ ────────▶ │ transcription        │
│                │              │   one turn           │           │ (gpt-transcribe, or  │
│ pill           │ ◀─────────── │ session              │ ◀──────── │ gpt-live-transcribe) │
│                │  delta, live │   runs the dictation │  text     └──────────────────────┘
│ focused field  │ ◀─────────── │ refiner              │ ────────▶ ┌──────────────────────┐
└────────────────┘  done        │   rewrite, then      │ ◀──────── │ language model       │
                                │   translate if asked │           │ (Responses API)      │
                                └──────────────────────┘           └──────────────────────┘
```

The app owns the machine: the shortcuts, the microphone, the pill, typing, the history of what was dictated, which it keeps on the Mac with the recording of each dictation, and the statistics of how much was dictated and what it cost. The server owns the speech pipeline and the OpenAI key. They talk over one WebSocket per dictation, described in [the protocol](protocol.md).

## A dictation

A dictation has two phases, and its text has two states.

1. **While the speaker talks**, the audio is recorded. With live transcription on, it is also transcribed as it comes, and the text heard so far is a **draft**: the pill can show it, dimmed, and nothing is typed.
2. **When the speaker stops**, the transcript is completed and a language model rewrites all of it, then translates it if asked. The **refined** text is typed into the focused field, once.

Typing once, at the end, is what keeps the text consistent. A sentence can only be written well when what follows it is known: where it ends, whether the speaker corrects it, how it connects to the next one. Text typed into another app also cannot be taken back reliably, so nothing is typed before it is final.

The price is that the text appears after the speaker stops, not during the speech. That wait is the transcript, about 0.7 s, plus the refinement, which grows with the length of the dictation. Rewriting half a minute of speech takes between 1 and 2 s. Translation adds the time of a second request.

## Transcription

A dictation is transcribed as **one turn**: the model hears each sentence together with what comes next. It punctuates across pauses, and it recognizes words better than it does on audio cut into pieces: a pause in the middle of a sentence does not end the sentence. There are two ways to do it, and the app chooses one with each dictation.

- **Once recorded**, the default. The [recording transcriber](../apps/server/src/recording.ts) keeps the audio on the server while the speaker talks, and sends all of it to `gpt-transcribe` as one file when they stop. Nothing is shown while they talk. It costs about a quarter of live transcription, and the text is typed at about the same time: either way, the speaker waits for the whole transcript and then the refinement. The transcript has 60 s to come back, plus a tenth of the recording's length.
- **Live**, when the speaker turns it on. The [live transcriber](../apps/server/src/transcriber.ts) streams the audio to an OpenAI realtime transcription session and commits it once, when the speaker stops. `gpt-live-transcribe` writes text while it listens, a little behind the voice, and that text only grows: it is the draft the pill shows. After the commit the model returns the complete transcript. If the model goes silent for 5 s before it comes, the text heard so far stands in for it.

Both models get the same hints, from the speaker's profile and their dictionary, and every part of a long recording gets them:

- **What their recordings are like**: a short description of who speaks, in which languages, and about what, as the prompt. OpenAI's guidance is to use it to describe the recording or its setting.
- **The languages they speak**, in place of the server's own setting, so the model does not have to tell the language.
- **The names and terms they use**, as keywords to listen for.

They are hints: a word that only sounds like a term can still be written as heard, and the refinement looks again. And a hint never fails a dictation. OpenAI refuses a request over a hint it does not take, such as a language it does not know, or a prompt longer than 1024 characters for the live model, so the server cuts the prompt to 1000 for both models and cleans up the languages and the terms first. Should OpenAI refuse the hints all the same, the recording, or the live session, is transcribed again without them, with the server's own languages, and the dictation goes on.

OpenAI takes files of up to 25 MB, about nine minutes of this audio. A recording longer than five minutes is sent in parts of at most five minutes, transcribed four at a time and joined in order. Each cut is at the quietest tenth of a second in the 30 s before the limit, so it falls in a pause and not in a word. A part does not hear the one before it, so the words right at a cut are recognized with less context: a cut every five minutes costs little.

Recording never waits for a connection. The app records from the moment the shortcut is pressed and sends the audio as it comes. Audio that arrives before the transcription session is ready waits for it, and a speaker who stops before then is waited for too: the audio is transcribed once the session is ready, up to 10 s after the start.

## Refinement

The refiner sends the complete transcript to a language model to remove fillers and false starts, apply the speaker's own corrections, and fix misheard words and punctuation. [Refiner source](../apps/server/src/refiner.ts).

- **One rewrite.** The model sees the whole text, so the result reads as one piece.
- **The speaker's instructions.** The app sends the instructions of the speaker's profile with the dictation: how they want their text written, and enough about what they talk about to tell what a misheard term was. They are added to the rewrite, and to the translation if there is one, and take precedence over the server's instructions. The rewrite needs them even when the text is translated: it is the request that fixes misheard terms.
- **The speaker's dictionary.** The app keeps a list of the speaker's names and terms, and sends it with each dictation. The rewrite is given it to tell what a misheard word was: a word that sounds like a term becomes the term where the context fits, such as "cloud" for "Claude" in a sentence about a model, and stays as it is where it means something else. The translation is told to keep the terms as written.
- **The text before the cursor.** When the dictation starts, the app reads the end of the text before the cursor in the focused field, through the Accessibility API, and sends it with the dictation. The model is given it apart from the transcript, in both requests, as context only: to spell names and terms the way the field does, match its register, and write a dictation that goes on with an unfinished sentence as the rest of it, without a capital letter. It never rewrites, repeats, or obeys that text. The server then puts a space before the result when it would otherwise run into the text before it, so the app types it as it comes. Reading the field is bounded to a few tens of milliseconds and happens once the microphone is opening, so recording never waits for it: an app that is busy or does not say gives no context. Password fields are never read, and the setting Use text in the field turns it off, since that text goes to OpenAI too. A failed dictation tried again from the history has no context: the field focused then is another, and its text is not typed. The transcription does not get the context: its prompt describes the setting of a recording, not the text it follows, and it holds 1024 characters at most.
- **Translation.** The app can ask for the text in another language. That takes a second request, after the first: the model is given the rewritten text, and told to write what the speaker meant the way a native writer would, with that language's own idioms and expressions, and not word for word. Asked to rewrite and translate at once, it follows the speaker's words too closely. The speaker waits for both requests, and both are counted in what the dictation cost.
- **Over a WebSocket.** The requests go through the Responses API on a WebSocket that the server opens when the dictation starts. When the speaker stops, the connection is already there, and the answers stream back on it.
- **It cannot lose text.** Refinement has 60 s in all. In each request, the model has 5 s to send its next event. If either limit is reached, the model fails, or a request returns nothing, the transcript is typed as it was heard, untranslated.

## The profile

What the models are told about the speaker is their profile: the instructions for the refinement, the description of their recordings and the languages they speak for the transcription. The app keeps it, and sends it with each dictation.

The speaker does not write it. An agent writes it in a conversation with them, by voice, on the app's Profile page. The page has the same shortcuts as a dictation, but what is said there goes to the agent, and nothing is typed:

1. The agent opens with a question, which the app asks at once, without a model.
2. The speaker answers with the shortcut. Their words fill in a message as they are heard, transcribed live as in a dictation, with their profile as hints.
3. When they stop, the transcript goes to the agent as it is, without a rewrite. The agent answers in JSON that follows a schema: first its reply, then the whole profile when it changed it, and the terms the speaker asked to add to their dictionary. The server passes the reply on as it is written, so it shows about a second after the speaker stops, and the profile follows a second or two later.

The agent asks one short question at a time, in the speaker's language, and follows up on what is missing: what they do, what they talk about, which languages they mix and how, how they want their text written. It writes the profile from the first answer, says when it has enough, and from then on answers. The speaker can keep talking to change it, or ask it to undo a change: the conversation has each version of the profile the agent wrote. A developer who dictates in Portuguese about Git, with the terms in English, gets instructions that keep "merge" and "rebase" in English and say what they are misheard as, a description of their recordings with those terms spelled out, Portuguese and English as their languages, and the terms themselves, suggested for their dictionary.

The profile is only changed through the conversation, and the terms only go to the dictionary when the speaker accepts them, with a click or by asking the agent. A turn that fails changes nothing. Without a connection, a turn is not recorded to send again, as a dictation is: the page says there is no connection, and the speaker answers again. A turn is short, and what is said to the agent is not kept.

Nothing the speaker says is kept. The conversation is held in the app's memory until it quits: it is not in the history, not counted in the statistics, and not logged, and each turn sends it whole, so the server keeps nothing either. Only the profile, and the terms accepted, are kept. See [the protocol](protocol.md#the-profile-conversation).

## Cost

A dictation is charged twice by OpenAI: the transcription by the minute of audio, and the refinement by the token. The refinement reports the tokens it read and wrote. Nothing reports a price, so the server holds the prices in its configuration and sends an estimate of the cost with the text.

The app adds up what each dictation used, day by day, and shows it on its Statistics page with how much was dictated and how fast. Those figures are counted as dictations happen and kept apart from the history, so they stay when a transcription is deleted.

## Failure

Nothing said is lost to a connection. The app keeps the whole recording of each dictation, and the recording never depends on the server: whatever happens to the connection, the microphone records until the speaker stops or cancels.

- On the server, a transcription failure ends the dictation with an error. One that could not reach OpenAI says so: `unreachable`. A transcription session that is not ready within 10 s of the start ends the dictation with a timeout. So does a dictation that hears nothing and gets no transcript in time after the stop.
- In the app, a session that fails while the speaker talks does not end the recording. The server counts as unreachable when it does not answer within 5 s, or refuses at once. When the session has no connection, the pill shows a small sign, and the live draft stops growing.
- When the speaker stops, a dictation whose session failed sends its whole recording once more, as a new dictation that is not live, at once instead of at the pace it was spoken. If that brings text, it is typed as usual. A dictation that was not live and failed after the stop is not sent again: the server already had the whole recording, and transcribing it once more would fail the same way.
- If there is still no text, the dictation is kept in the app's history with its recording, marked as not transcribed, and the app types the draft it has, if any. The history can send the recording again by hand. Nothing is retried by itself.
- Cancelling types nothing, and keeps nothing.
- The app shows a failure in the pill for three seconds: no microphone access, no microphone, no connection, or transcription failed, and whether the dictation was saved to the history.

## Why these choices

- **Native Swift app.** The product depends on a system-wide shortcut on a single modifier key, a window that floats over every app without taking focus, and typing into other apps. These are native macOS APIs.
- **A separate server.** The OpenAI key and the pipeline stay out of the app, so the pipeline can change without shipping the app, and the same server can run on another machine. On one Mac, the production app carries the server and runs it while it runs, with the key from the server's own `.env`.
- **The server owns the text.** The app shows what the server sends and types what `done` carries. It does not assemble or correct text itself: even the space that separates a dictation from the text before the cursor comes from the server, which knows the language and the punctuation.
- **One refinement at the end.** Refining pieces while the speaker talks types text sooner, but each piece is written without knowing what follows, and the pieces do not read as one text. Rewriting the whole transcript together trades that speed for a coherent result.
