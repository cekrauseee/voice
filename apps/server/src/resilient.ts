import type { Logger } from "@voice/log";
import type { CreateTranscriber, Transcriber, TranscriberEvents } from "./transcriber.ts";

export interface ResilientEvents extends TranscriberEvents {
  /**
   * The provider session was replaced. Every turn that is not final yet is transcribed
   * again from its beginning: the text heard for it so far is void.
   */
  restarted(): void;
}

export interface ResilientOptions {
  /** A session older than this is replaced at the next commit, before the provider ends it. */
  maxSessionMs?: number;
  /** Failures in a row, without the session getting ready in between, before giving up. */
  maxFailures?: number;
  /** How long to wait before opening another session after a failure. Doubles each time. */
  retryDelayMs?: number;
  log: Logger;
}

export type CreateResilientTranscriber = (events: ResilientEvents) => Transcriber;

const MAX_SESSION_MS = 50 * 60_000;
const MAX_FAILURES = 5;
const RETRY_DELAY_MS = 1_000;

interface Turn {
  /** The audio, kept until the turn is final so that it can be sent again. */
  chunks: Buffer[];
  committed: boolean;
  done: boolean;
}

interface Session {
  transcriber: Transcriber;
  /** The turns sent to this session, in order: the session numbers them by this index. */
  sent: number[];
  openedAt: number;
  closed: boolean;
}

/**
 * A transcriber that outlives its provider sessions.
 *
 * It keeps the audio of every turn until the turn is final. When the session fails, or
 * has lived long enough to be ended by the provider, it opens another and sends those
 * turns again. The caller sees one transcriber, with one numbering of turns.
 */
export function createResilientTranscriber(
  create: CreateTranscriber,
  options: ResilientOptions,
): CreateResilientTranscriber {
  const {
    maxSessionMs = MAX_SESSION_MS,
    maxFailures = MAX_FAILURES,
    retryDelayMs = RETRY_DELAY_MS,
    log,
  } = options;
  return (events) => {
    const turns: Turn[] = [];
    /** The turn that audio goes to: the one after the last commit. */
    let open = 0;
    let session: Session | undefined;
    let failures = 0;
    let wasReady = false;
    let retry: NodeJS.Timeout | undefined;
    let closed = false;

    const turn = (index: number): Turn => {
      let current = turns[index];
      if (!current) {
        current = { chunks: [], committed: false, done: false };
        turns[index] = current;
      }
      return current;
    };

    const connect = (): Session => {
      const current: Session = {
        transcriber: { append() {}, commit() {}, close() {} },
        sent: [],
        openedAt: Date.now(),
        closed: false,
      };
      current.transcriber = create({
        ready: () => {
          if (current.closed) return;
          failures = 0;
          if (!wasReady) {
            wasReady = true;
            events.ready();
          }
        },
        delta: (local, text) => {
          const index = current.sent[local];
          if (current.closed || index === undefined || turns[index]?.done) return;
          events.delta(index, text);
        },
        final: (local, text) => {
          const index = current.sent[local];
          const done = index === undefined ? undefined : turns[index];
          if (current.closed || index === undefined || !done || done.done) return;
          done.done = true;
          done.chunks = [];
          events.final(index, text);
        },
        error: (error) => {
          if (current.closed || closed) return;
          current.closed = true;
          current.transcriber.close();
          session = undefined;
          failures += 1;
          if (failures >= maxFailures) {
            log.error("transcription gave up", { failures, error: error.message });
            events.error(error);
            return;
          }
          const delay = retryDelayMs * 2 ** (failures - 1);
          log.warn("transcription session lost", {
            error: error.message,
            failures,
            retry_ms: delay,
          });
          retry = setTimeout(restart, delay);
        },
      });
      return current;
    };

    /** Makes sure a session knows a turn, so that it numbers it. */
    const introduce = (current: Session, index: number) => {
      if (current.sent.at(-1) !== index) current.sent.push(index);
    };

    /** Opens another session and sends it every turn that is not final yet. */
    const restart = () => {
      if (closed) return;
      if (session) {
        session.closed = true;
        session.transcriber.close();
      }
      events.restarted();
      const current = connect();
      session = current;
      turns.forEach((pending, index) => {
        if (pending.done || (pending.chunks.length === 0 && !pending.committed)) return;
        introduce(current, index);
        for (const pcm of pending.chunks) current.transcriber.append(pcm);
        if (pending.committed) current.transcriber.commit();
      });
    };

    session = connect();
    return {
      append(pcm) {
        if (closed) return;
        turn(open).chunks.push(pcm);
        if (session) {
          introduce(session, open);
          session.transcriber.append(pcm);
        }
      },
      commit() {
        if (closed) return;
        turn(open).committed = true;
        if (session) {
          introduce(session, open);
          session.transcriber.commit();
        }
        open += 1;
        if (session && Date.now() - session.openedAt >= maxSessionMs) {
          log.info("transcription session rotated", { age_ms: Date.now() - session.openedAt });
          restart();
        }
      },
      close() {
        closed = true;
        clearTimeout(retry);
        session?.transcriber.close();
        session = undefined;
      },
    };
  };
}
