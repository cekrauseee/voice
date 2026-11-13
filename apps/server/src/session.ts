import type { Logger } from "@voice/log";
import {
  BYTES_PER_SECOND,
  type ErrorCode,
  type Prices,
  type ServerMessage,
  usage,
} from "./protocol.ts";
import type { CreateRefiner, Refinement, Refiner } from "./refiner.ts";
import type { CreateTranscriber, Transcriber } from "./transcriber.ts";

/** How long transcription may take to be ready for audio. */
const READY_TIMEOUT_MS = 10_000;
/** How long the transcriber may send nothing once the speaker has stopped. */
const TRANSCRIPT_TIMEOUT_MS = 5_000;
/** A refinement slower than this is dropped and the transcript is used as is. */
const REFINE_TIMEOUT_MS = 60_000;

export interface SessionDeps {
  createTranscriber: CreateTranscriber;
  createRefiner: CreateRefiner;
  /** What the dictation is charged at, to tell the client what it cost. */
  prices: Prices;
  send(message: ServerMessage): void;
  /** Called once when the session is over. No message follows. */
  end(): void;
  log: Logger;
}

/** What a dictation runs on, from the moment the client starts it. */
interface Started {
  transcriber: Transcriber;
  refiner: Refiner;
  /** How the speaker wants the text written. */
  instructions: string;
}

/**
 * One dictation: audio in, one refined text out.
 *
 * The audio is transcribed as a single turn while the speaker talks, and the text heard is
 * passed on as it comes. When the speaker stops, the complete transcript is refined in one
 * request, and its result ends the dictation.
 */
export class DictationSession {
  private readonly deps: SessionDeps;
  private readonly abort = new AbortController();
  private readonly startedAt = Date.now();
  private started: Started | undefined;
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

  constructor(deps: SessionDeps) {
    this.deps = deps;
  }

  /** The client opens the dictation, with how the speaker wants the text written. */
  start(instructions: string): void {
    if (this.ended) return;
    if (this.started) {
      this.reject();
      return;
    }
    this.started = {
      transcriber: this.deps.createTranscriber({
        ready: () => this.onReady(),
        delta: (_turn, text) => this.onDelta(text),
        final: (_turn, text) => this.onFinal(text),
        error: (error) => this.onError(error),
      }),
      refiner: this.deps.createRefiner(),
      instructions,
    };
    this.readyTimer = setTimeout(() => {
      this.deps.log.error("transcription not ready", { timeout_ms: READY_TIMEOUT_MS });
      this.fail("timeout", "Transcription timed out");
    }, READY_TIMEOUT_MS);
    this.deps.log.info("started", { instructions_chars: instructions.trim().length });
  }

  audio(pcm: Buffer): void {
    if (this.ended || this.stoppedAt !== undefined) return;
    if (!this.started) {
      this.reject();
      return;
    }
    this.audioBytes += pcm.length;
    this.started.transcriber.append(pcm);
  }

  /** The client finished speaking: complete the transcript, refine it, then end. */
  stop(): void {
    if (this.ended || this.stoppedAt !== undefined) return;
    if (!this.started) {
      this.reject();
      return;
    }
    this.stoppedAt = Date.now();
    this.started.transcriber.commit();
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

  /** Gives the transcriber a fresh `TRANSCRIPT_TIMEOUT_MS` to send what comes next. */
  private awaitTranscript(): void {
    clearTimeout(this.transcriptTimer);
    this.transcriptTimer = setTimeout(() => this.onTranscriptTimeout(), TRANSCRIPT_TIMEOUT_MS);
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
    this.deps.log.error("transcription failed", { error: error.message });
    this.fail("transcription_failed", "Transcription failed");
  }

  private async finish(transcript: string): Promise<void> {
    const started = this.started;
    if (this.ended || !started) return;
    this.transcribed = true;
    clearTimeout(this.transcriptTimer);
    this.deps.log.info("transcribed", {
      transcript_ms: Date.now() - (this.stoppedAt ?? Date.now()),
      chars: transcript.length,
    });
    const unrefined = { text: transcript, inputTokens: 0, outputTokens: 0 };
    const refined = transcript === "" ? unrefined : await this.refine(transcript, started);
    if (this.ended) return;
    const used = usage(
      this.deps.prices,
      this.audioBytes / BYTES_PER_SECOND,
      refined.inputTokens,
      refined.outputTokens,
    );
    this.deps.log.info("used", { ...used });
    this.send({ type: "done", text: refined.text, usage: used });
    this.end("done");
  }

  /**
   * Returns the refined text, or the transcript when refining does not work out. The
   * tokens of a refinement that returned nothing are still counted: they were paid for.
   */
  private async refine(
    transcript: string,
    { refiner, instructions }: Started,
  ): Promise<Refinement> {
    const log = this.deps.log;
    const startedAt = Date.now();
    const signal = AbortSignal.any([this.abort.signal, AbortSignal.timeout(REFINE_TIMEOUT_MS)]);
    try {
      const refined = await refiner.refine({ text: transcript, instructions }, signal);
      if (refined.text !== "") {
        log.info("refined", { refine_ms: Date.now() - startedAt, chars: refined.text.length });
        return refined;
      }
      log.warn("refinement empty", { refine_ms: Date.now() - startedAt });
      return { ...refined, text: transcript };
    } catch (error) {
      if (!this.ended) {
        log.warn("refinement failed", {
          refine_ms: Date.now() - startedAt,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
    return { text: transcript, inputTokens: 0, outputTokens: 0 };
  }

  private fail(code: ErrorCode, message: string): void {
    this.send({ type: "error", code, message });
    this.end(code);
  }

  private send(message: ServerMessage): void {
    if (!this.ended) this.deps.send(message);
  }

  private end(outcome: "done" | "cancelled" | ErrorCode): void {
    if (this.ended) return;
    this.ended = true;
    this.deps.log.info("ended", { outcome, duration_ms: Date.now() - this.startedAt });
    clearTimeout(this.readyTimer);
    clearTimeout(this.transcriptTimer);
    this.abort.abort();
    this.started?.transcriber.close();
    this.started?.refiner.close();
    this.deps.end();
  }
}
