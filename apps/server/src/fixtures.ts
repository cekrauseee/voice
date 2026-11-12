import { createLogger } from "@voice/log";
import { SAMPLE_RATE } from "./protocol.ts";
import type { CreateRefiner, RefineInput } from "./refiner.ts";
import type { CreateTranscriber, TranscriberEvents } from "./transcriber.ts";

/** Audio of a given length. */
export function audio(ms: number): Buffer {
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
export class FakeRefiner {
  readonly calls: {
    input: RefineInput;
    signal: AbortSignal;
    resolve(text: string): void;
    reject(error: Error): void;
  }[] = [];
  created = 0;
  closed = false;

  readonly create: CreateRefiner = () => {
    this.created += 1;
    return {
      refine: (input, signal) => {
        const { promise, resolve, reject } = Promise.withResolvers<string>();
        this.calls.push({ input, signal, resolve, reject });
        return promise;
      },
      close: () => {
        this.closed = true;
      },
    };
  };
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

/** A logger that writes nowhere. */
export const silent = createLogger({ scope: "test", write: () => {} });
