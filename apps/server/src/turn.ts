import type { Logger } from "@voice/log";
import { BYTES_PER_SECOND, type ErrorCode, type Prices } from "./protocol.ts";
import {
  type CreateTranscriber,
  isUnreachable,
  type Transcriber,
  type TranscriptionHints,
} from "./transcriber.ts";

/** How long transcription may take to be ready for audio. */
const READY_TIMEOUT_MS = 10_000;
/** How long the live transcriber may send nothing once the speaker has stopped. */
const TRANSCRIPT_TIMEOUT_MS = 5_000;
/**
 * How long a recording may take to be transcribed once the speaker has stopped, plus a tenth
 * of its length: a long one is sent in parts.
 */
const RECORDING_TIMEOUT_MS = 60_000;

/** The messages a turn sends by itself, whatever it is for. */
export type TurnMessage =
  | { type: "ready" }
  | { type: "delta"; text: string }
  | { type: "error"; code: ErrorCode; message: string };

export interface TurnDeps<Message> {
  /** Transcribes the recording once the speaker stops. */
  createTranscriber: CreateTranscriber;
  /** Transcribes while the speaker talks. */
  createLiveTranscriber: CreateTranscriber;
  send(message: TurnMessage | Message): void;
  /** Called once when the turn is over. No message follows. */
  end(): void;
  log: Logger;
}

/** What a turn has when its transcript is complete. */
export interface Answering<Message> {
  /** Seconds of audio the client sent. */
  audioSeconds: number;
  /** Whether the audio was transcribed while the speaker talked. */
  live: boolean;
  /** Aborted when the turn ends early, as when the client goes away. */
  signal: AbortSignal;
  send(message: Message): void;
}

/** What a turn does once the speaker has been heard. */
export interface TurnResponse<Message> {
  /**
   * Answers the complete transcript, and resolves with the outcome of the turn: `done`, or the
   * code of the error it sent. Never rejects.
   */
  respond(transcript: string, answering: Answering<Message>): Promise<string>;
  close(): void;
}

/** The prices a turn is charged at: live transcription has its own. */
export function chargedAt(prices: Prices, live: boolean): Prices {
  return live ? { ...prices, transcribeMinute: prices.liveTranscribeMinute } : prices;
}

/**
 * One turn of speech: audio in, one answer out.
 *
 * The audio is transcribed as a single turn: once the speaker stops, or, live, while they
 * talk, with the text heard passed on as it comes. When the transcript is complete, it is
 * answered, and the answer ends the turn. A dictation answers with refined text, the profile
 * conversation with the agent's reply.
 */
export class SpeechTurn<Message> {
  private readonly deps: TurnDeps<Message>;
  private readonly abort = new AbortController();
  private readonly startedAt = Date.now();
  private transcriber: Transcriber | undefined;
  private response: TurnResponse<Message> | undefined;
  /** Whether the audio is transcribed while the speaker talks. */
  private live = false;
  /** The text heard so far. */
  private heard = "";
  /** How much audio the client sent. */
  private audioBytes = 0;
  private ready = false;
  private stoppedAt: number | undefined;
  /** Set once the transcript is complete. Nothing from the transcriber matters after it. */
  private transcribed = false;
  private readyTimer: NodeJS.Timeout | undefined;
  private transcriptTimer: NodeJS.Timeout | undefined;
  private ended = false;

  constructor(deps: TurnDeps<Message>) {
    this.deps = deps;
  }

  /**
   * Starts transcribing with the hints, live or once the speaker stops, and makes what will
   * answer the transcript. Returns false when the turn has started already, which ends it, or
   * is over.
   */
  begin(hints: TranscriptionHints, live: boolean, respond: () => TurnResponse<Message>): boolean {
    if (this.ended) return false;
    if (this.transcriber) {
      this.reject();
      return false;
    }
    this.live = live;
    const createTranscriber = live ? this.deps.createLiveTranscriber : this.deps.createTranscriber;
    this.transcriber = createTranscriber(
      {
        ready: () => this.onReady(),
        delta: (_turn, text) => this.onDelta(text),
        final: (_turn, text) => this.onFinal(text),
        error: (error) => this.onError(error),
        hintsRejected: ({ code, param }) => {
          this.deps.log.warn("transcription hints rejected", {
            code,
            param,
            hint: "the transcription goes on without them",
          });
        },
      },
      hints,
    );
    this.response = respond();
    this.readyTimer = setTimeout(() => {
      this.deps.log.error("transcription not ready", { timeout_ms: READY_TIMEOUT_MS });
      this.fail("timeout", "Transcription timed out");
    }, READY_TIMEOUT_MS);
    return true;
  }

  audio(pcm: Buffer): void {
    if (this.ended || this.stoppedAt !== undefined) return;
    if (!this.transcriber) {
      this.reject();
      return;
    }
    this.audioBytes += pcm.length;
    this.transcriber.append(pcm);
  }

  /** The client finished speaking: complete the transcript, answer it, then end. */
  stop(): void {
    if (this.ended || this.stoppedAt !== undefined) return;
    if (!this.transcriber) {
      this.reject();
      return;
    }
    this.stoppedAt = Date.now();
    this.transcriber.commit();
    // Audio sent before transcription is ready waits for it, and so does the transcript.
    if (this.ready) this.awaitTranscript();
  }

  /** The client sent something that is not part of the protocol. */
  reject(): void {
    this.fail("bad_request", "Unexpected message");
  }

  /** The client went away: drop everything. */
  close(): void {
    this.end("cancelled");
  }

  private onReady(): void {
    this.ready = true;
    clearTimeout(this.readyTimer);
    this.send({ type: "ready" });
    if (this.stoppedAt !== undefined && !this.transcribed) this.awaitTranscript();
  }

  /**
   * Gives the transcriber a fresh while to send what comes next: a live one sends text as it
   * goes, and a recording takes the time to be transcribed whole.
   */
  private awaitTranscript(): void {
    clearTimeout(this.transcriptTimer);
    const timeout = this.live
      ? TRANSCRIPT_TIMEOUT_MS
      : RECORDING_TIMEOUT_MS + (this.audioBytes / BYTES_PER_SECOND) * 100;
    this.transcriptTimer = setTimeout(() => this.onTranscriptTimeout(), timeout);
  }

  private onDelta(text: string): void {
    if (this.transcribed) return;
    if (this.stoppedAt !== undefined) this.awaitTranscript();
    // The first words arrive with a space before them.
    const delta = this.heard === "" ? text.trimStart() : text;
    if (delta === "") return;
    this.heard += delta;
    this.send({ type: "delta", text: delta });
  }

  private onFinal(text: string): void {
    if (this.stoppedAt === undefined || this.transcribed) return;
    void this.finish(text.trim());
  }

  /** The transcriber went silent before completing the transcript. What was heard stands in. */
  private onTranscriptTimeout(): void {
    const heard = this.heard.trim();
    if (heard === "") {
      this.fail("timeout", "Transcription timed out");
    } else {
      this.deps.log.warn("transcript timed out", { chars: heard.length });
      void this.finish(heard);
    }
  }

  private onError(error: Error): void {
    if (this.transcribed) return;
    if (isUnreachable(error)) {
      this.deps.log.error("transcription unreachable", {
        error: error.message,
        hint: "check the network of the server",
      });
      this.fail("unreachable", "OpenAI could not be reached");
      return;
    }
    this.deps.log.error("transcription failed", { error: error.message });
    this.fail("transcription_failed", "Transcription failed");
  }

  private async finish(transcript: string): Promise<void> {
    const response = this.response;
    if (this.ended || !response) return;
    this.transcribed = true;
    clearTimeout(this.transcriptTimer);
    this.deps.log.info("transcribed", {
      transcript_ms: Date.now() - (this.stoppedAt ?? Date.now()),
      chars: transcript.length,
    });
    const outcome = await response.respond(transcript, {
      audioSeconds: this.audioBytes / BYTES_PER_SECOND,
      live: this.live,
      signal: this.abort.signal,
      send: (message) => this.send(message),
    });
    this.end(outcome);
  }

  private fail(code: ErrorCode, message: string): void {
    this.send({ type: "error", code, message });
    this.end(code);
  }

  private send(message: TurnMessage | Message): void {
    if (!this.ended) this.deps.send(message);
  }

  private end(outcome: string): void {
    if (this.ended) return;
    this.ended = true;
    this.deps.log.info("ended", { outcome, duration_ms: Date.now() - this.startedAt });
    clearTimeout(this.readyTimer);
    clearTimeout(this.transcriptTimer);
    this.abort.abort();
    this.transcriber?.close();
    this.response?.close();
    this.deps.end();
  }
}
