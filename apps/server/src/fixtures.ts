import { SAMPLE_RATE } from "./protocol.ts";
import type { RefineInput, Refiner } from "./refiner.ts";
import type { CreateTranscriber, TranscriberEvents } from "./transcriber.ts";

/** A loud 220 Hz tone, which the segmenter hears as speech. */
export function speech(ms: number): Buffer {
  const samples = (SAMPLE_RATE * ms) / 1000;
  const pcm = Buffer.alloc(samples * 2);
  for (let i = 0; i < samples; i++) {
    pcm.writeInt16LE(Math.round(8000 * Math.sin((2 * Math.PI * 220 * i) / SAMPLE_RATE)), i * 2);
  }
  return pcm;
}

export function silence(ms: number): Buffer {
  return Buffer.alloc(((SAMPLE_RATE * ms) / 1000) * 2);
}

/** A transcriber driven by the test: it records what it receives and emits what it is told. */
export class FakeTranscriber {
  events!: TranscriberEvents;
  bytes = 0;
  commits = 0;
  closed = false;

  readonly create: CreateTranscriber = (events) => {
    this.events = events;
    return {
      append: (pcm) => {
        this.bytes += pcm.length;
      },
      commit: () => {
        this.commits += 1;
      },
      close: () => {
        this.closed = true;
      },
    };
  };
}

/** A refiner whose calls resolve when the test says so. */
export class FakeRefiner implements Refiner {
  readonly calls: {
    input: RefineInput;
    resolve(text: string): void;
    reject(error: Error): void;
  }[] = [];

  refine(input: RefineInput): Promise<string> {
    const { promise, resolve, reject } = Promise.withResolvers<string>();
    this.calls.push({ input, resolve, reject });
    return promise;
  }
}

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
