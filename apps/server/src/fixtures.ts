import { createLogger } from "@voice/log";
import { type Prices, SAMPLE_RATE, type Usage } from "./protocol.ts";
import type { CreateRefiner, RefineInput, Refinement } from "./refiner.ts";
import type { CreateTranscriber, Transcriber, TranscriberEvents } from "./transcriber.ts";

/** Audio of a given length. */
export function audio(ms: number): Buffer {
  return Buffer.alloc(((SAMPLE_RATE * ms) / 1000) * 2);
}

/** A loud 220 Hz tone, which the segmenter hears as speech. */
export function speech(ms: number): Buffer {
  const samples = (SAMPLE_RATE * ms) / 1000;
  const buffer = Buffer.alloc(samples * 2);
  for (let i = 0; i < samples; i++) {
    buffer.writeInt16LE(Math.round(8000 * Math.sin((2 * Math.PI * 220 * i) / SAMPLE_RATE)), i * 2);
  }
  return buffer;
}

/** Digital silence. */
export function silence(ms: number): Buffer {
  return audio(ms);
}

/** A transcriber driven by the test: it records what it receives and emits what it is told. */
export class FakeTranscriber implements Transcriber {
  events!: TranscriberEvents;
  /** The audio appended, chunk by chunk. */
  readonly appended: Buffer[] = [];
  commits = 0;
  closed = false;

  readonly create: CreateTranscriber = (events) => {
    this.events = events;
    return this;
  };

  get bytes(): number {
    return this.appended.reduce((sum, chunk) => sum + chunk.length, 0);
  }

  append(pcm: Buffer): void {
    this.appended.push(pcm);
  }

  commit(): void {
    this.commits += 1;
  }

  close(): void {
    this.closed = true;
  }
}

/** Makes a fake transcriber for each session opened, and keeps them all. */
export class FakeTranscribers {
  readonly all: FakeTranscriber[] = [];

  readonly create: CreateTranscriber = (events) => {
    const transcriber = new FakeTranscriber();
    this.all.push(transcriber);
    return transcriber.create(events);
  };

  /** The session opened last. */
  get last(): FakeTranscriber {
    const last = this.all.at(-1);
    if (!last) throw new Error("No transcriber was created");
    return last;
  }
}

/** A refiner whose calls resolve when the test says so. */
export class FakeRefiner {
  readonly calls: {
    input: RefineInput;
    signal: AbortSignal;
    /** Answers with the text, and with the tokens it took: what it read, what it wrote. */
    resolve(text: string, tokens?: [input: number, output: number]): void;
    reject(error: Error): void;
  }[] = [];
  created = 0;
  closed = false;

  readonly create: CreateRefiner = () => {
    this.created += 1;
    return {
      refine: (input, signal) => {
        const { promise, resolve, reject } = Promise.withResolvers<Refinement>();
        this.calls.push({
          input,
          signal,
          resolve: (text, [inputTokens, outputTokens] = [0, 0]) =>
            resolve({ text, inputTokens, outputTokens }),
          reject,
        });
        return promise;
      },
      close: () => {
        this.closed = true;
      },
    };
  };
}

/** Prices that make round numbers: a cent a second, and a dollar or two a thousand tokens. */
export const prices: Prices = { transcribeMinute: 0.6, refineInput: 1000, refineOutput: 2000 };

/** A dictation that used nothing. */
export const unused: Usage = { audio_seconds: 0, input_tokens: 0, output_tokens: 0, cost: 0 };

/** Lets pending promise callbacks run. */
export function settle(): Promise<void> {
  return new Promise((resolve) => setImmediate(resolve));
}

/** Waits until a condition holds. */
export async function until(condition: () => boolean): Promise<void> {
  const deadline = Date.now() + 2000;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error("Condition was not met in time");
    await new Promise((resolve) => setTimeout(resolve, 2));
  }
}

/** A logger that writes nowhere. */
export const silent = createLogger({ scope: "test", write: () => {} });
