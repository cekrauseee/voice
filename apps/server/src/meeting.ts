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
  type Usage,
  usage,
} from "./protocol.ts";
import { createResilientTranscriber } from "./resilient.ts";
import type { CreateTranscriber } from "./transcriber.ts";

/** How long transcription may take to be ready for audio. */
const READY_TIMEOUT_MS = 10_000;
/** How long the channels may take to pass on their last segments after the stop. */
const DRAIN_TIMEOUT_MS = 8_000;

export interface MeetingDeps {
  createTranscriber: CreateTranscriber;
  /** What the audio is charged at, to tell the client what the meeting cost. */
  prices: Prices;
  send(message: MeetingServerMessage): void;
  /** Called once when the session is over. No message follows. */
  end(): void;
  log: Logger;
}

/**
 * One connection of a meeting: two channels of audio in, segments of text out.
 *
 * Each channel is cut into turns at its pauses and transcribed live. The client keeps the
 * transcript: the session numbers the segments from where the client says, and ends when
 * the client stops or goes away.
 */
export class MeetingSession {
  private readonly deps: MeetingDeps;
  private readonly startedAt = Date.now();
  private channels: Record<ChannelName, Channel> | undefined;
  private readonly ready = new Set<ChannelName>();
  private readonly drained = new Set<ChannelName>();
  private nextId = 1;
  private segments = 0;
  private stopped = false;
  private ended = false;
  private readyTimer: NodeJS.Timeout | undefined;
  private drainTimer: NodeJS.Timeout | undefined;

  constructor(deps: MeetingDeps) {
    this.deps = deps;
  }

  /** The client opens the meeting: where its clocks are, and the id of the next segment. */
  start(message: MeetingStart): void {
    if (this.ended) return;
    if (this.channels) {
      this.reject();
      return;
    }
    this.nextId = message.first_id;
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

  /** The meeting is over: the last segments follow, then `done`. */
  stop(): void {
    if (this.ended || this.stopped) return;
    if (!this.channels) {
      this.reject();
      return;
    }
    this.stopped = true;
    for (const name of CHANNELS) this.channels[name].stop();
    if (!this.ended) {
      this.drainTimer = setTimeout(() => {
        this.deps.log.warn("segments left behind", { timeout_ms: DRAIN_TIMEOUT_MS });
        this.finish();
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

  private onSegment(channel: ChannelName, segment: ChannelSegment): void {
    const id = this.nextId;
    this.nextId += 1;
    this.segments += 1;
    this.send({ type: "segment", id, channel, ...segment });
    this.send({ type: "usage", usage: this.usage() });
    this.deps.log.debug("segment", {
      id,
      channel,
      duration_ms: Math.round((segment.end - segment.start) * 1000),
      chars: segment.text.length,
    });
  }

  private onDrained(name: ChannelName): void {
    this.drained.add(name);
    if (this.drained.size === CHANNELS.length) this.finish();
  }

  private onError(channel: ChannelName, error: Error): void {
    this.deps.log.error("transcription failed", { channel, error: error.message });
    this.fail("transcription_failed", "Transcription failed");
  }

  private finish(): void {
    if (this.ended) return;
    const used = this.usage();
    this.deps.log.info("used", { ...used });
    this.send({ type: "done", usage: used });
    this.end("done");
  }

  /** What the connection used so far: the speech sent to be transcribed. */
  private usage(): Usage {
    const bytes = CHANNELS.reduce((sum, name) => sum + (this.channels?.[name].speechBytes ?? 0), 0);
    return usage(this.deps.prices, bytes / BYTES_PER_SECOND, 0, 0);
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
    for (const name of CHANNELS) this.channels?.[name].close();
    this.deps.end();
  }
}
