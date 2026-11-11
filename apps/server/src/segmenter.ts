import { SAMPLE_RATE } from "./protocol.ts";

const FRAME_MS = 20;
const FRAME_BYTES = ((SAMPLE_RATE * FRAME_MS) / 1000) * 2;

/** Quietest level treated as speech, in dBFS. */
const MIN_SPEECH_DB = -55;
/** How far above the noise floor a frame must be to count as speech. */
const SPEECH_MARGIN_DB = 12;
/** The noise floor follows quiet frames at once and rises slowly, so speech does not lift it. */
const FLOOR_RISE_DB_PER_FRAME = 0.01;
const MAX_FLOOR_DB = -35;
const MIN_LEVEL_DB = -90;

export interface SegmenterOptions {
  /** Silence that ends a segment. */
  pauseMs: number;
  /** Past this length, a segment ends at the next short pause. */
  softMaxMs: number;
  shortPauseMs: number;
  /** Past this length, a segment ends even mid-speech. */
  hardMaxMs: number;
  /** Speech needed to open a segment. */
  onsetMs: number;
  /** Audio kept from before the onset, so the first word is not clipped. */
  preRollMs: number;
}

export const defaultSegmenterOptions: SegmenterOptions = {
  pauseMs: 600,
  softMaxMs: 12_000,
  shortPauseMs: 200,
  hardMaxMs: 20_000,
  onsetMs: 60,
  preRollMs: 300,
};

export type SegmenterAction = { type: "audio"; pcm: Buffer } | { type: "commit" };

/**
 * Splits a PCM stream into speech segments.
 *
 * Audio is forwarded only while a segment is open, and each segment ends with a
 * commit: at a pause, or at the length limits when the speaker does not pause.
 */
export class Segmenter {
  private readonly options: SegmenterOptions;
  private remainder: Buffer = Buffer.alloc(0);
  private preRoll: Buffer[] = [];
  private open = false;
  private onsetFrames = 0;
  private silenceFrames = 0;
  private segmentFrames = 0;
  private floorDb = MIN_SPEECH_DB - SPEECH_MARGIN_DB;

  constructor(options: SegmenterOptions = defaultSegmenterOptions) {
    this.options = options;
  }

  push(pcm: Buffer): SegmenterAction[] {
    const data = this.remainder.length > 0 ? Buffer.concat([this.remainder, pcm]) : pcm;
    const actions: SegmenterAction[] = [];
    let audio: Buffer[] = [];
    const flushAudio = () => {
      if (audio.length > 0) {
        actions.push({ type: "audio", pcm: Buffer.concat(audio) });
        audio = [];
      }
    };

    let offset = 0;
    for (; offset + FRAME_BYTES <= data.length; offset += FRAME_BYTES) {
      const frame = data.subarray(offset, offset + FRAME_BYTES);
      const speech = this.isSpeech(frame);

      if (!this.open) {
        const onset = frames(this.options.onsetMs);
        this.preRoll.push(frame);
        if (this.preRoll.length > frames(this.options.preRollMs) + onset) this.preRoll.shift();
        this.onsetFrames = speech ? this.onsetFrames + 1 : 0;
        if (this.onsetFrames >= onset) {
          this.open = true;
          this.segmentFrames = this.preRoll.length;
          this.silenceFrames = 0;
          audio.push(...this.preRoll);
          this.preRoll = [];
        }
        continue;
      }

      audio.push(frame);
      this.segmentFrames += 1;
      this.silenceFrames = speech ? 0 : this.silenceFrames + 1;
      if (this.shouldCommit()) {
        flushAudio();
        actions.push({ type: "commit" });
        this.close();
      }
    }

    flushAudio();
    this.remainder = Buffer.from(data.subarray(offset));
    return actions;
  }

  /** Ends the stream, committing the open segment. */
  flush(): SegmenterAction[] {
    const actions: SegmenterAction[] = [];
    if (this.open) {
      const tail = this.remainder.subarray(0, this.remainder.length & ~1);
      if (tail.length > 0) actions.push({ type: "audio", pcm: tail });
      actions.push({ type: "commit" });
    }
    this.remainder = Buffer.alloc(0);
    this.close();
    return actions;
  }

  private shouldCommit(): boolean {
    const { pauseMs, softMaxMs, shortPauseMs, hardMaxMs } = this.options;
    const silenceMs = this.silenceFrames * FRAME_MS;
    const segmentMs = this.segmentFrames * FRAME_MS;
    return (
      silenceMs >= pauseMs ||
      (segmentMs >= softMaxMs && silenceMs >= shortPauseMs) ||
      segmentMs >= hardMaxMs
    );
  }

  private close(): void {
    this.open = false;
    this.preRoll = [];
    this.onsetFrames = 0;
    this.silenceFrames = 0;
    this.segmentFrames = 0;
  }

  private isSpeech(frame: Buffer): boolean {
    const db = levelDb(frame);
    this.floorDb =
      db < this.floorDb ? db : Math.min(this.floorDb + FLOOR_RISE_DB_PER_FRAME, MAX_FLOOR_DB);
    return db > Math.max(this.floorDb + SPEECH_MARGIN_DB, MIN_SPEECH_DB);
  }
}

function frames(ms: number): number {
  return Math.ceil(ms / FRAME_MS);
}

/** RMS level of a PCM16 frame in dBFS. */
function levelDb(frame: Buffer): number {
  let sum = 0;
  for (let i = 0; i < frame.length; i += 2) {
    const sample = frame.readInt16LE(i);
    sum += sample * sample;
  }
  const rms = Math.sqrt(sum / (frame.length / 2));
  return Math.max(20 * Math.log10(rms / 32_768), MIN_LEVEL_DB);
}
