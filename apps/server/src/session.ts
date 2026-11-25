import type { Logger } from "@voice/log";
import { normalizeLanguages, normalizePrompt } from "./hints.ts";
import { joinAfter } from "./joining.ts";
import { type Prices, type ServerMessage, type Start, usage } from "./protocol.ts";
import { type CreateRefiner, type Refinement, RefinementError, type Refiner } from "./refiner.ts";
import type { CreateTranscriber } from "./transcriber.ts";
import { type Answering, chargedAt, SpeechTurn } from "./turn.ts";
import { normalizeVocabulary } from "./vocabulary.ts";

/** A refinement slower than this is dropped and the transcript is used as is. */
const REFINE_TIMEOUT_MS = 60_000;

export interface SessionDeps {
  /** Transcribes the recording once the speaker stops. */
  createTranscriber: CreateTranscriber;
  /** Transcribes while the speaker talks. */
  createLiveTranscriber: CreateTranscriber;
  createRefiner: CreateRefiner;
  /** What the dictation is charged at, to tell the client what it cost. */
  prices: Prices;
  send(message: ServerMessage): void;
  /** Called once when the session is over. No message follows. */
  end(): void;
  log: Logger;
}

/** What the refinement is asked for. */
type Wanted = Omit<Start, "transcriptionPrompt" | "languages" | "live">;

/**
 * One dictation: audio in, one refined text out.
 *
 * The audio is transcribed as one turn, once the speaker stops, or, live, while they talk,
 * with the text heard passed on as it comes. The complete transcript is refined, and the
 * result ends the dictation.
 */
export class DictationSession {
  private readonly deps: SessionDeps;
  private readonly turn: SpeechTurn<ServerMessage>;

  constructor(deps: SessionDeps) {
    this.deps = deps;
    this.turn = new SpeechTurn<ServerMessage>(deps);
  }

  /**
   * The client opens the dictation, with how and in what language the speaker wants the text,
   * the names and terms they use, the text the dictation follows in the field, whether it is
   * transcribed while they talk, and what their recordings are like.
   */
  start({
    instructions = "",
    translateTo = "",
    vocabulary: terms = [],
    context = "",
    live = false,
    transcriptionPrompt = "",
    languages: codes = [],
  }: Partial<Start> = {}): void {
    const vocabulary = normalizeVocabulary(terms);
    const prompt = normalizePrompt(transcriptionPrompt);
    const languages = normalizeLanguages(codes);
    const wanted: Wanted = { instructions, translateTo, vocabulary, context };
    const started = this.turn.begin({ keywords: vocabulary, prompt, languages }, live, () => {
      const refiner = this.deps.createRefiner();
      return {
        respond: (transcript, answering) => this.respond(transcript, refiner, wanted, answering),
        close: () => refiner.close(),
      };
    });
    if (!started) return;
    this.deps.log.info("started", {
      instructions_chars: instructions.trim().length,
      live,
      translates: translateTo.trim() !== "",
      vocabulary_terms: vocabulary.length,
      context_chars: context.length,
      prompt_chars: prompt.length,
      languages: languages.length,
    });
  }

  audio(pcm: Buffer): void {
    this.turn.audio(pcm);
  }

  /** The client finished speaking: complete the transcript, refine it, then end. */
  stop(): void {
    this.turn.stop();
  }

  /** The client sent something that is not part of the protocol. */
  reject(): void {
    this.turn.reject();
  }

  /** The client went away: drop everything. */
  close(): void {
    this.turn.close();
  }

  /** Refines the transcript and sends it, with what the dictation used. */
  private async respond(
    transcript: string,
    refiner: Refiner,
    wanted: Wanted,
    { audioSeconds, live, signal, send }: Answering<ServerMessage>,
  ): Promise<string> {
    const unrefined = { text: transcript, inputTokens: 0, outputTokens: 0 };
    const refined =
      transcript === "" ? unrefined : await this.refine(transcript, refiner, wanted, signal);
    const used = usage(
      chargedAt(this.deps.prices, live),
      audioSeconds,
      refined.inputTokens,
      refined.outputTokens,
    );
    if (signal.aborted) return "cancelled";
    this.deps.log.info("used", { ...used });
    // The text goes right after the text before the cursor, and may need a space to follow it.
    send({ type: "done", text: joinAfter(wanted.context, refined.text), usage: used });
    return "done";
  }

  /**
   * Returns the refined text, or the transcript when refining does not work out.
   * The tokens of completed requests are counted either way.
   */
  private async refine(
    transcript: string,
    refiner: Refiner,
    { instructions, translateTo, vocabulary, context }: Wanted,
    ended: AbortSignal,
  ): Promise<Refinement> {
    const log = this.deps.log;
    const startedAt = Date.now();
    const signal = AbortSignal.any([ended, AbortSignal.timeout(REFINE_TIMEOUT_MS)]);
    try {
      const refined = await refiner.refine(
        { text: transcript, instructions, translateTo, vocabulary, context },
        signal,
      );
      if (refined.text !== "") {
        log.info("refined", { refine_ms: Date.now() - startedAt, chars: refined.text.length });
        return refined;
      }
      log.warn("refinement empty", { refine_ms: Date.now() - startedAt });
      return { ...refined, text: transcript };
    } catch (error) {
      if (!ended.aborted) {
        log.warn("refinement failed", {
          refine_ms: Date.now() - startedAt,
          error: error instanceof Error ? error.message : String(error),
        });
      }
      if (error instanceof RefinementError) {
        return {
          text: transcript,
          inputTokens: error.inputTokens,
          outputTokens: error.outputTokens,
        };
      }
      return { text: transcript, inputTokens: 0, outputTokens: 0 };
    }
  }
}
