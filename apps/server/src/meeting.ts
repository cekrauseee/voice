import type { Logger } from "@voice/log";
import { Channel, type ChannelSegment } from "./channel.ts";
import {
  BYTES_PER_SECOND,
  CHANNELS,
  type Channel as ChannelName,
  type ErrorCode,
  type MeetingServerMessage,
  type MeetingStart,
  type Prices,
  type Segment,
  type Usage,
  usage,
} from "./protocol.ts";
import { createResilientTranscriber } from "./resilient.ts";
import type { CreateReviser, RevisedPiece, Reviser } from "./reviser.ts";
import type { CreateTranscriber } from "./transcriber.ts";
import { defaultWindowOptions, type WindowOptions, Windows } from "./windows.ts";

/** How long transcription may take to be ready for audio. */
const READY_TIMEOUT_MS = 10_000;
/** How long the channels may take to pass on their last segments after the stop. */
const DRAIN_TIMEOUT_MS = 8_000;
/** A revision slower than this is dropped and the window keeps its text. */
const REVISE_TIMEOUT_MS = 60_000;
/** How long the revisions left may take after the stop. */
const REVISION_DRAIN_TIMEOUT_MS = 90_000;
/** How much of the revised transcript a revision sees before its window. */
const CONTEXT_CHARS = 1_200;

export interface MeetingDeps {
  createTranscriber: CreateTranscriber;
  createReviser: CreateReviser;
  /** What the audio and the tokens are charged at, to tell the client what the meeting cost. */
  prices: Prices;
  /** Where the windows that are revised are cut. */
  windows?: WindowOptions;
  send(message: MeetingServerMessage): void;
  /** Called once when the session is over. No message follows. */
  end(): void;
  log: Logger;
}

/**
 * One connection of a meeting: two channels of audio in, segments of text out, and the
 * segments revised in windows as the meeting goes.
 *
 * Each channel is cut into turns at its pauses and transcribed live. The segments are
 * grouped into windows of a few minutes, and each window is revised by a language model
 * with the window before it as context, one at a time, in order; transcription never
 * waits for it. The client keeps the transcript: the session numbers the segments from
 * where the client says, and ends when the client stops or goes away.
 */
export class MeetingSession {
  private readonly deps: MeetingDeps;
  private readonly startedAt = Date.now();
  private readonly abort = new AbortController();
  private readonly windows: Windows;
  private channels: Record<ChannelName, Channel> | undefined;
  private reviser: Reviser | undefined;
  private instructions = "";
  private readonly ready = new Set<ChannelName>();
  private readonly drained = new Set<ChannelName>();
  private nextId = 1;
  private segments = 0;
  /** The windows waiting to be revised, oldest first. */
  private readonly queue: Segment[][] = [];
  private revising = false;
  /** The end of the revised transcript, which the next revision sees. */
  private context = "";
  private inputTokens = 0;
  private outputTokens = 0;
  private stopped = false;
  /** The channels sent their last segment: only the revisions are left. */
  private channelsDone = false;
  private ended = false;
  private readyTimer: NodeJS.Timeout | undefined;
  private drainTimer: NodeJS.Timeout | undefined;
  private revisionTimer: NodeJS.Timeout | undefined;

  constructor(deps: MeetingDeps) {
    this.deps = deps;
    this.windows = new Windows(deps.windows ?? defaultWindowOptions);
  }

  /** The client opens the meeting: where its clocks are, and the id of the next segment. */
  start(message: MeetingStart): void {
    if (this.ended) return;
    if (this.channels) {
      this.reject();
      return;
    }
    this.nextId = message.first_id;
    this.instructions = message.instructions;
    const channel = (name: ChannelName): Channel => {
      const log = this.deps.log.child({ fields: { channel: name } });
      return new Channel(
        createResilientTranscriber(this.deps.createTranscriber, { log }),
        {
          ready: () => this.onReady(name),
          draft: (text) => this.send({ type: "draft", channel: name, text }),
          segment: (segment) => this.onSegment(name, segment),
          drained: () => this.onDrained(name),
          error: (error) => this.onError(name, error),
        },
        { offset: message.offsets[name] },
        log,
      );
    };
    this.channels = { me: channel("me"), others: channel("others") };
    this.reviser = this.deps.createReviser();
    this.readyTimer = setTimeout(() => {
      this.deps.log.error("transcription not ready", { timeout_ms: READY_TIMEOUT_MS });
      this.fail("timeout", "Transcription timed out");
    }, READY_TIMEOUT_MS);
    this.deps.log.info("started", {
      first_id: message.first_id,
      offset_me: message.offsets.me,
      offset_others: message.offsets.others,
      instructions_chars: message.instructions.trim().length,
    });
  }

  audio(channel: ChannelName, pcm: Buffer): void {
    if (this.ended || this.stopped) return;
    if (!this.channels) {
      this.reject();
      return;
    }
    this.channels[channel].audio(pcm);
  }

  /** The meeting is over: the last segments follow, then the revisions left, then `done`. */
  stop(): void {
    if (this.ended || this.stopped) return;
    if (!this.channels) {
      this.reject();
      return;
    }
    this.stopped = true;
    for (const name of CHANNELS) this.channels[name].stop();
    if (!this.ended && !this.channelsDone) {
      this.drainTimer = setTimeout(() => {
        this.deps.log.warn("segments left behind", { timeout_ms: DRAIN_TIMEOUT_MS });
        this.onChannelsDone();
      }, DRAIN_TIMEOUT_MS);
    }
  }

  /** The client sent something that is not part of the protocol. */
  reject(): void {
    this.fail("bad_request", "Unexpected message");
  }

  /** The client went away. It keeps what it got, and may come back on another connection. */
  close(): void {
    this.end("closed");
  }

  private onReady(name: ChannelName): void {
    this.ready.add(name);
    if (this.ready.size < CHANNELS.length) return;
    clearTimeout(this.readyTimer);
    this.deps.log.info("ready", { ready_ms: Date.now() - this.startedAt });
    this.send({ type: "ready" });
  }

  private onSegment(channel: ChannelName, heard: ChannelSegment): void {
    const segment: Segment = { id: this.nextId, channel, ...heard };
    this.nextId += 1;
    this.segments += 1;
    this.send({ type: "segment", ...segment });
    this.send({ type: "usage", usage: this.usage() });
    this.deps.log.debug("segment", {
      id: segment.id,
      channel,
      duration_ms: Math.round((segment.end - segment.start) * 1000),
      chars: segment.text.length,
    });
    const closed = this.windows.push(segment);
    if (closed) this.enqueue(closed);
  }

  private onDrained(name: ChannelName): void {
    this.drained.add(name);
    if (this.drained.size === CHANNELS.length) this.onChannelsDone();
  }

  /** No more segments will come. What is left of the window is revised, then it is done. */
  private onChannelsDone(): void {
    if (this.ended || this.channelsDone) return;
    this.channelsDone = true;
    clearTimeout(this.drainTimer);
    const rest = this.windows.flush();
    if (rest) this.enqueue(rest);
    if (this.queue.length === 0 && !this.revising) {
      this.finish();
      return;
    }
    this.revisionTimer = setTimeout(() => {
      this.deps.log.warn("revisions left behind", {
        timeout_ms: REVISION_DRAIN_TIMEOUT_MS,
        windows: this.queue.length + (this.revising ? 1 : 0),
      });
      this.finish();
    }, REVISION_DRAIN_TIMEOUT_MS);
  }

  private onError(channel: ChannelName, error: Error): void {
    this.deps.log.error("transcription failed", { channel, error: error.message });
    this.fail("transcription_failed", "Transcription failed");
  }

  private enqueue(window: Segment[]): void {
    this.queue.push(window);
    void this.drain();
  }

  /** Revises the windows one at a time, in order: each continues the one before it. */
  private async drain(): Promise<void> {
    if (this.revising) return;
    this.revising = true;
    for (;;) {
      const window = this.queue.shift();
      if (!window || this.ended) break;
      await this.revise(window);
    }
    this.revising = false;
    if (this.channelsDone && !this.ended) this.finish();
  }

  /** Revises a window, trying twice. A window that cannot be revised keeps its text. */
  private async revise(window: Segment[]): Promise<void> {
    const reviser = this.reviser;
    const [first, last] = [window[0], window.at(-1)];
    if (!reviser || !first || !last) return;
    const log = this.deps.log;
    for (let attempt = 1; attempt <= 2 && !this.ended; attempt++) {
      const startedAt = Date.now();
      const signal = AbortSignal.any([this.abort.signal, AbortSignal.timeout(REVISE_TIMEOUT_MS)]);
      try {
        const revision = await reviser.revise(
          { context: this.context, segments: window, instructions: this.instructions },
          signal,
        );
        if (this.ended) return;
        this.inputTokens += revision.inputTokens;
        this.outputTokens += revision.outputTokens;
        const segments = this.place(revision.pieces, window);
        this.send({ type: "revised", from: first.id, to: last.id, segments });
        this.send({ type: "usage", usage: this.usage() });
        this.context = contextOf(segments);
        log.info("revised", {
          from: first.id,
          to: last.id,
          revise_ms: Date.now() - startedAt,
          pieces: segments.length,
          chars: segments.reduce((sum, s) => sum + s.text.length, 0),
        });
        return;
      } catch (error) {
        if (this.ended) return;
        log.warn("revision failed", {
          from: first.id,
          to: last.id,
          attempt,
          revise_ms: Date.now() - startedAt,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
    // The text heard stands, and is what the next window continues.
    this.context = contextOf(window);
  }

  /**
   * Gives the revised pieces of a window their ids and times. A piece covers the segments
   * from the one it begins in up to the one the next piece begins in.
   */
  private place(pieces: RevisedPiece[], window: Segment[]): Segment[] {
    return pieces.map((piece, index) => {
      const next = pieces[index + 1]?.anchor ?? Number.POSITIVE_INFINITY;
      const covered = window.filter((s) => s.id >= piece.anchor && s.id < next);
      const base = covered.length > 0 ? covered : window.filter((s) => s.id === piece.anchor);
      const id = this.nextId;
      this.nextId += 1;
      return {
        id,
        channel: piece.channel,
        start: Math.min(...base.map((s) => s.start)),
        end: Math.max(...base.map((s) => s.end)),
        text: piece.text,
      };
    });
  }

  private finish(): void {
    if (this.ended) return;
    const used = this.usage();
    this.deps.log.info("used", { ...used });
    this.send({ type: "done", usage: used });
    this.end("done");
  }

  /** What the connection used so far: the speech sent to be transcribed, and the tokens. */
  private usage(): Usage {
    const bytes = CHANNELS.reduce((sum, name) => sum + (this.channels?.[name].speechBytes ?? 0), 0);
    return usage(this.deps.prices, bytes / BYTES_PER_SECOND, this.inputTokens, this.outputTokens);
  }

  private fail(code: ErrorCode, message: string): void {
    this.send({ type: "error", code, message });
    this.end(code);
  }

  private send(message: MeetingServerMessage): void {
    if (!this.ended) this.deps.send(message);
  }

  private end(outcome: "done" | "closed" | ErrorCode): void {
    if (this.ended) return;
    this.ended = true;
    this.deps.log.info("ended", {
      outcome,
      segments: this.segments,
      duration_ms: Date.now() - this.startedAt,
    });
    clearTimeout(this.readyTimer);
    clearTimeout(this.drainTimer);
    clearTimeout(this.revisionTimer);
    this.abort.abort();
    for (const name of CHANNELS) this.channels?.[name].close();
    this.reviser?.close();
    this.deps.end();
  }
}

/** The end of a stretch of the transcript, as a dialog, for the revision after it. */
function contextOf(segments: Segment[]): string {
  const side = { me: "me", others: "others" };
  return segments
    .map((s) => `${side[s.channel]}: ${s.text}`)
    .join("\n")
    .slice(-CONTEXT_CHARS);
}
