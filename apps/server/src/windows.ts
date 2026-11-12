import type { Segment } from "./protocol.ts";

export interface WindowOptions {
  /** A window is long enough once it spans this many seconds of the meeting... */
  minSeconds: number;
  /** ...and holds this many words. */
  minWords: number;
  /** A long enough window closes before a segment that comes after a silence this long. */
  gapSeconds: number;
  /** Past this span, a window closes before the next segment, silence or not. */
  maxSeconds: number;
}

export const defaultWindowOptions: WindowOptions = {
  minSeconds: 120,
  minWords: 150,
  gapSeconds: 1.5,
  maxSeconds: 240,
};

/**
 * Groups the segments of a meeting, as they are sent, into the windows that are revised.
 *
 * A window closes at a boundary between segments: once it is long enough and the next
 * segment comes after a pause, or once it has gone on too long. So a revision sees a few
 * minutes of the conversation with its sentences whole, more often than not.
 */
export class Windows {
  private readonly options: WindowOptions;
  private open: Segment[] = [];

  constructor(options: WindowOptions = defaultWindowOptions) {
    this.options = options;
  }

  /** Adds a segment. Returns the window its arrival closed, if it closed one. */
  push(segment: Segment): Segment[] | undefined {
    let closed: Segment[] | undefined;
    if (this.open.length > 0) {
      const { minSeconds, minWords, gapSeconds, maxSeconds } = this.options;
      const span = this.end - this.start;
      const enough = span >= minSeconds && this.words >= minWords;
      if ((enough && segment.start - this.end >= gapSeconds) || span >= maxSeconds) {
        closed = this.open;
        this.open = [];
      }
    }
    this.open.push(segment);
    return closed;
  }

  /** Closes the open window, if there is one. */
  flush(): Segment[] | undefined {
    if (this.open.length === 0) return undefined;
    const closed = this.open;
    this.open = [];
    return closed;
  }

  private get start(): number {
    return Math.min(...this.open.map((s) => s.start));
  }

  private get end(): number {
    return Math.max(...this.open.map((s) => s.end));
  }

  private get words(): number {
    return this.open.reduce((sum, s) => sum + countWords(s.text), 0);
  }
}

export function countWords(text: string): number {
  return text.split(/\s+/).filter((word) => word !== "").length;
}
