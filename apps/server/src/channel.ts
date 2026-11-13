import type { Logger } from "@voice/log";
import type { CreateResilientTranscriber } from "./resilient.ts";
import {
  defaultSegmenterOptions,
  Segmenter,
  type SegmenterAction,
  type SegmenterOptions,
} from "./segmenter.ts";
import type { Transcriber } from "./transcriber.ts";

export interface ChannelSegment {
  /** Seconds since the meeting started. */
  start: number;
  end: number;
  text: string;
}

export interface ChannelEvents {
  ready(): void;
  /** The text heard that is not in a segment yet. It replaces the draft shown so far. */
  draft(text: string): void;
  /** A stretch of speech, with its text. Segments come in the order they were spoken. */
  segment(segment: ChannelSegment): void;
  /** The channel was stopped and every segment is out. */
  drained(): void;
  /** The channel cannot transcribe any more. */
  error(error: Error): void;
}

export interface ChannelOptions {
  /** Where the channel's clock starts, in seconds. */
  offset?: number;
  segmenter?: SegmenterOptions;
  /** How long a committed turn may take to complete before the text heard stands in. */
  transcriptTimeoutMs?: number;
}

const TRANSCRIPT_TIMEOUT_MS = 5_000;

interface Turn {
  start: number;
  /** Set when the turn is committed. */
  end?: number;
  /** The text heard so far. */
  heard: string;
  /** The text of the segment, once the turn is final or has waited long enough. */
  text?: string;
  timer?: NodeJS.Timeout;
}

/**
 * One side of a meeting: its audio cut into turns at the pauses, transcribed, and passed
 * on as segments in the order they were spoken.
 *
 * The segmenter opens and commits turns; the transcriber numbers them in the same order.
 */
export class Channel {
  private readonly events: ChannelEvents;
  private readonly segmenter: Segmenter;
  private readonly transcriber: Transcriber;
  private readonly timeoutMs: number;
  private readonly log: Logger;
  private readonly turns: Turn[] = [];
  /** The next turn to pass on as a segment. */
  private next = 0;
  private draft = "";
  private stopped = false;
  private drained = false;
  private closed = false;
  /** Bytes of speech sent to be transcribed, which is what is paid for. */
  speechBytes = 0;

  constructor(
    create: CreateResilientTranscriber,
    events: ChannelEvents,
    options: ChannelOptions,
    log: Logger,
  ) {
    this.events = events;
    this.segmenter = new Segmenter(
      options.segmenter ?? defaultSegmenterOptions,
      options.offset ?? 0,
    );
    this.timeoutMs = options.transcriptTimeoutMs ?? TRANSCRIPT_TIMEOUT_MS;
    this.log = log;
    this.transcriber = create({
      ready: () => events.ready(),
      delta: (turn, text) => this.onDelta(turn, text),
      final: (turn, text) => this.onFinal(turn, text),
      restarted: () => this.onRestarted(),
      error: (error) => events.error(error),
    });
  }

  audio(pcm: Buffer): void {
    if (this.stopped || this.closed) return;
    this.apply(this.segmenter.push(pcm));
  }

  /** No more audio: the open turn is committed, and the segments still pending follow. */
  stop(): void {
    if (this.stopped || this.closed) return;
    this.stopped = true;
    this.apply(this.segmenter.flush());
    this.drainIfDone();
  }

  close(): void {
    this.closed = true;
    for (const turn of this.turns) clearTimeout(turn.timer);
    this.transcriber.close();
  }

  private apply(actions: SegmenterAction[]): void {
    for (const action of actions) {
      switch (action.type) {
        case "open":
          this.turns.push({ start: action.start, heard: "" });
          break;
        case "audio":
          this.speechBytes += action.pcm.length;
          this.transcriber.append(action.pcm);
          break;
        case "commit": {
          const turn = this.turns.at(-1);
          if (!turn || turn.end !== undefined) break;
          turn.end = action.end;
          this.transcriber.commit();
          turn.timer = setTimeout(() => this.onTimeout(turn), this.timeoutMs);
          break;
        }
      }
    }
  }

  private onDelta(index: number, text: string): void {
    const turn = this.turns[index];
    if (!turn || turn.text !== undefined) return;
    turn.heard += text;
    this.updateDraft();
  }

  private onFinal(index: number, text: string): void {
    const turn = this.turns[index];
    if (!turn || turn.text !== undefined || turn.end === undefined) return;
    this.settle(turn, text.trim());
  }

  /** The turn did not complete in time. What was heard stands in. */
  private onTimeout(turn: Turn): void {
    if (turn.text !== undefined) return;
    this.log.warn("transcript timed out", { chars: turn.heard.trim().length });
    this.settle(turn, turn.heard.trim());
  }

  /** The transcriber starts over on the turns that are not final: so does their text. */
  private onRestarted(): void {
    for (const turn of this.turns.slice(this.next)) {
      if (turn.text === undefined) turn.heard = "";
    }
    this.updateDraft();
  }

  private settle(turn: Turn, text: string): void {
    clearTimeout(turn.timer);
    turn.text = text;
    // Segments go out in the order they were spoken: a turn waits for the ones before it.
    for (;;) {
      const ready = this.turns[this.next];
      if (!ready || ready.text === undefined || ready.end === undefined) break;
      if (ready.text !== "") {
        this.events.segment({ start: ready.start, end: ready.end, text: ready.text });
      }
      this.next += 1;
    }
    this.updateDraft();
    this.drainIfDone();
  }

  private updateDraft(): void {
    const draft = this.turns
      .slice(this.next)
      .map((turn) => (turn.text ?? turn.heard).trim())
      .filter((text) => text !== "")
      .join(" ");
    if (draft === this.draft) return;
    this.draft = draft;
    this.events.draft(draft);
  }

  private drainIfDone(): void {
    if (this.drained || !this.stopped || this.next < this.turns.length) return;
    this.drained = true;
    this.events.drained();
  }
}
