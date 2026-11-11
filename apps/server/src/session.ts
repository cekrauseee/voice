import type { Logger } from "@voice/log";
import type { ErrorCode, ServerMessage } from "./protocol.ts";
import type { Refiner } from "./refiner.ts";
import { Segmenter, type SegmenterAction } from "./segmenter.ts";
import type { CreateTranscriber, Transcriber } from "./transcriber.ts";

/** A refinement slower than this is dropped and the transcript is used as is. */
const REFINE_TIMEOUT_MS = 5_000;
/** How long the pipeline may take to drain after the client stops. */
const FINISH_TIMEOUT_MS = 15_000;
/** How much of the refined text before a segment the refiner sees: the last few segments. */
const CONTEXT_CHARS = 600;

export interface SessionDeps {
  createTranscriber: CreateTranscriber;
  refiner: Refiner;
  send(message: ServerMessage): void;
  /** Called once when the session is over. No message follows. */
  end(): void;
  log: Logger;
}

interface Segment {
  live: string;
  final?: string;
  finalAt?: number;
  refined?: string;
}

/**
 * One dictation: audio in, refined segments out.
 *
 * Each segment is transcribed live and completed on commit. Completed segments are then
 * refined one at a time, in order, while the following ones keep transcribing.
 */
export class DictationSession {
  private readonly deps: SessionDeps;
  private readonly segmenter = new Segmenter();
  private readonly transcriber: Transcriber;
  private readonly abort = new AbortController();
  private readonly segments: Segment[] = [];
  private readonly committedAt: number[] = [];
  private readonly startedAt = Date.now();
  /** The segment to refine next. Every segment before it is refined and sent. */
  private next = 0;
  private refining = false;
  private stopped = false;
  private ended = false;
  private finishTimer: NodeJS.Timeout | undefined;

  constructor(deps: SessionDeps) {
    this.deps = deps;
    this.transcriber = deps.createTranscriber({
      ready: () => this.send({ type: "ready" }),
      delta: (segment, text) => this.onDelta(segment, text),
      final: (segment, text) => this.onFinal(segment, text),
      error: (error) => {
        this.deps.log.error("transcription failed", { error: error.message });
        this.fail("transcription_failed", "Transcription failed");
      },
    });
    this.deps.log.info("started");
  }

  audio(pcm: Buffer): void {
    if (this.stopped || this.ended) return;
    this.apply(this.segmenter.push(pcm));
  }

  /** The client finished speaking: drain the pipeline, then end. */
  stop(): void {
    if (this.stopped || this.ended) return;
    this.stopped = true;
    this.apply(this.segmenter.flush());
    this.finishTimer = setTimeout(
      () => this.fail("timeout", "Transcription timed out"),
      FINISH_TIMEOUT_MS,
    );
    this.finishIfDrained();
  }

  /** The client sent something that is not part of the protocol. */
  reject(): void {
    this.fail("bad_request", "Unexpected message");
  }

  /** The client went away: drop everything. */
  close(): void {
    this.end("cancelled");
  }

  private apply(actions: SegmenterAction[]): void {
    for (const action of actions) {
      if (action.type === "audio") {
        this.transcriber.append(action.pcm);
      } else {
        this.transcriber.commit();
        this.committedAt.push(Date.now());
      }
    }
  }

  private segment(index: number): Segment {
    let segment = this.segments[index];
    if (!segment) {
      segment = { live: "" };
      this.segments[index] = segment;
    }
    return segment;
  }

  private onDelta(index: number, text: string): void {
    const segment = this.segment(index);
    if (segment.final !== undefined) return;
    segment.live += text;
    this.send({ type: "delta", segment: index, text });
  }

  private onFinal(index: number, text: string): void {
    const segment = this.segment(index);
    if (segment.final !== undefined) return;
    segment.final = text.trim();
    segment.finalAt = Date.now();
    this.send({ type: "final", segment: index, text: segment.final });
    void this.drain();
  }

  /**
   * Refines the completed segments one at a time, in the order they were spoken. A segment
   * continues the text before it, so it waits for that text to be refined first.
   */
  private async drain(): Promise<void> {
    if (this.refining) return;
    this.refining = true;
    for (;;) {
      const index = this.next;
      const segment = this.segments[index];
      if (this.ended || segment?.final === undefined) break;
      const text = segment.final === "" ? "" : await this.refine(index, segment);
      if (this.ended) break;
      segment.refined = text;
      this.send({ type: "refined", segment: index, text });
      this.next += 1;
    }
    this.refining = false;
    this.finishIfDrained();
  }

  /** Returns the refined text of a segment, or its transcript when refining does not work out. */
  private async refine(index: number, segment: Segment): Promise<string> {
    const log = this.deps.log.child({ fields: { segment: index } });
    const text = segment.final ?? "";
    const finalAt = segment.finalAt ?? Date.now();
    const startedAt = Date.now();
    const signal = AbortSignal.any([this.abort.signal, AbortSignal.timeout(REFINE_TIMEOUT_MS)]);
    let refined = text;
    try {
      const output = await this.deps.refiner.refine(
        { text, previous: this.previous(index) },
        signal,
      );
      if (isPlausible(text, output)) refined = output;
      else log.warn("refinement discarded", { chars: text.length, refined_chars: output.length });
    } catch (error) {
      if (this.ended) return text;
      log.warn("refinement failed", { error: errorMessage(error) });
    }
    log.info("segment refined", {
      final_ms: finalAt - (this.committedAt[index] ?? finalAt),
      wait_ms: startedAt - finalAt,
      refine_ms: Date.now() - startedAt,
      chars: refined.length,
    });
    return refined;
  }

  /** The end of the refined text before a segment: what the segment continues. */
  private previous(index: number): string {
    return this.segments
      .slice(0, index)
      .map((segment) => segment.refined ?? "")
      .filter((text) => text !== "")
      .join(" ")
      .slice(-CONTEXT_CHARS);
  }

  /** Ends the dictation once the client has stopped and every segment is refined. */
  private finishIfDrained(): void {
    if (this.ended || !this.stopped || this.next < this.committedAt.length) return;
    this.send({ type: "done" });
    this.end("done");
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
    this.deps.log.info("ended", {
      outcome,
      segments: this.committedAt.length,
      duration_ms: Date.now() - this.startedAt,
    });
    clearTimeout(this.finishTimer);
    this.abort.abort();
    this.transcriber.close();
    this.deps.end();
  }
}

/** Rejects output that is far longer than the segment: the model wrote, it did not clean up. */
function isPlausible(text: string, refined: string): boolean {
  return refined.length <= text.length * 2 + 40;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
