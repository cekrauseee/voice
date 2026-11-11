import type { ErrorCode, ServerMessage } from "./protocol.ts";
import type { Refiner } from "./refiner.ts";
import { Segmenter, type SegmenterAction } from "./segmenter.ts";
import type { CreateTranscriber, Transcriber } from "./transcriber.ts";

/** A refinement slower than this is dropped and the transcript is used as is. */
const REFINE_TIMEOUT_MS = 5_000;
/** How long the pipeline may take to drain after the client stops. */
const FINISH_TIMEOUT_MS = 15_000;
/** How much preceding text the refiner sees. */
const CONTEXT_CHARS = 600;

export interface SessionDeps {
  createTranscriber: CreateTranscriber;
  refiner: Refiner;
  send(message: ServerMessage): void;
  /** Called once when the session is over. No message follows. */
  end(): void;
  log(message: string): void;
}

interface Segment {
  live: string;
  final?: string;
  refined?: string;
}

/**
 * One dictation: audio in, refined segments out.
 *
 * Each segment is transcribed live, completed on commit, then refined on its own
 * while the following segments keep transcribing. Refined segments are sent in order.
 */
export class DictationSession {
  private readonly deps: SessionDeps;
  private readonly segmenter = new Segmenter();
  private readonly transcriber: Transcriber;
  private readonly abort = new AbortController();
  private readonly segments: Segment[] = [];
  private readonly committedAt: number[] = [];
  private emitted = 0;
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
        this.deps.log(`transcription error: ${error.message}`);
        this.fail("transcription_failed", "Transcription failed");
      },
    });
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
    this.emit();
  }

  /** The client went away: drop everything. */
  close(): void {
    this.end();
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
    this.send({ type: "final", segment: index, text: segment.final });
    if (segment.final === "") {
      segment.refined = "";
      this.emit();
    } else {
      void this.refine(index, segment, segment.final);
    }
  }

  private async refine(index: number, segment: Segment, text: string): Promise<void> {
    const finalAt = Date.now();
    const signal = AbortSignal.any([this.abort.signal, AbortSignal.timeout(REFINE_TIMEOUT_MS)]);
    let refined = text;
    try {
      const output = await this.deps.refiner.refine(
        { text, previous: this.previous(index) },
        signal,
      );
      if (isPlausible(text, output)) refined = output;
      else this.deps.log(`segment ${index}: refinement discarded`);
    } catch (error) {
      if (this.ended) return;
      this.deps.log(`segment ${index}: refinement failed: ${errorMessage(error)}`);
    }
    const committedAt = this.committedAt[index] ?? finalAt;
    this.deps.log(
      `segment ${index}: final ${finalAt - committedAt}ms, refined ${Date.now() - finalAt}ms`,
    );
    segment.refined = refined;
    this.emit();
  }

  /** The best text known for everything before a segment. */
  private previous(index: number): string {
    return this.segments
      .slice(0, index)
      .map((segment) => segment.refined ?? segment.final ?? segment.live)
      .filter((text) => text !== "")
      .join(" ")
      .slice(-CONTEXT_CHARS);
  }

  /** Sends the refined segments that are next in order, and ends once all are out. */
  private emit(): void {
    if (this.ended) return;
    for (;;) {
      const text = this.segments[this.emitted]?.refined;
      if (text === undefined) break;
      this.send({ type: "refined", segment: this.emitted, text });
      this.emitted += 1;
    }
    if (this.stopped && this.emitted === this.committedAt.length) {
      this.send({ type: "done" });
      this.end();
    }
  }

  private fail(code: ErrorCode, message: string): void {
    this.send({ type: "error", code, message });
    this.end();
  }

  private send(message: ServerMessage): void {
    if (!this.ended) this.deps.send(message);
  }

  private end(): void {
    if (this.ended) return;
    this.ended = true;
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
