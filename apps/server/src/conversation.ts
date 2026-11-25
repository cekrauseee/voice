import type { Logger } from "@voice/log";
import type { Agent, CreateAgent } from "./agent.ts";
import { normalizeLanguages, normalizePrompt } from "./hints.ts";
import {
  type Prices,
  type ProfileServerMessage,
  type ProfileStart,
  usage,
  wireProfile,
} from "./protocol.ts";
import type { CreateTranscriber } from "./transcriber.ts";
import { type Answering, chargedAt, SpeechTurn } from "./turn.ts";
import { normalizeVocabulary } from "./vocabulary.ts";

/** An answer slower than this is given up. */
const ANSWER_TIMEOUT_MS = 30_000;

export interface ConversationDeps {
  /** Transcribes the recording once the speaker stops. Not used: a turn is heard live. */
  createTranscriber: CreateTranscriber;
  /** Transcribes while the speaker talks, for their message to fill in as they speak. */
  createLiveTranscriber: CreateTranscriber;
  createAgent: CreateAgent;
  /** What the turn is charged at. */
  prices: Prices;
  send(message: ProfileServerMessage): void;
  /** Called once when the turn is over. No message follows. */
  end(): void;
  log: Logger;
}

/**
 * One turn of the conversation about the speaker's profile: what they say in, the agent's
 * answer out.
 *
 * What they say is transcribed live, as for a dictation, and passed on as it comes. When they
 * stop, the transcript goes to the agent as it is, without a rewrite. The agent's reply is
 * passed on as it is written, and the turn ends with the whole answer: the reply, and the
 * profile when the agent changed it. The server keeps nothing: the conversation so far comes
 * from the client with each turn.
 */
export class ProfileTurn {
  private readonly deps: ConversationDeps;
  private readonly turn: SpeechTurn<ProfileServerMessage>;

  constructor(deps: ConversationDeps) {
    this.deps = deps;
    this.turn = new SpeechTurn<ProfileServerMessage>(deps);
  }

  /** The client opens the turn, with the conversation so far and the profile as it is. */
  start({ history, profile, vocabulary: terms }: ProfileStart): void {
    const vocabulary = normalizeVocabulary(terms);
    // The speaker's own profile helps hear what they say about it.
    const prompt = normalizePrompt(profile.transcriptionPrompt);
    const languages = normalizeLanguages(profile.languages);
    // Always live: the speaker's message fills in as they speak.
    const started = this.turn.begin({ keywords: vocabulary, prompt, languages }, true, () => {
      const agent = this.deps.createAgent();
      return {
        respond: (said, answering) =>
          this.respond(said, agent, { history, profile, vocabulary }, answering),
        close: () => agent.close(),
      };
    });
    if (!started) return;
    // What was said is only measured.
    this.deps.log.info("started", {
      history_messages: history.length,
      history_chars: history.reduce((chars, entry) => chars + entry.text.length, 0),
      instructions_chars: profile.instructions.length,
      prompt_chars: prompt.length,
      languages: languages.length,
      terms: profile.terms.length,
      vocabulary_terms: vocabulary.length,
    });
  }

  audio(pcm: Buffer): void {
    this.turn.audio(pcm);
  }

  stop(): void {
    this.turn.stop();
  }

  reject(): void {
    this.turn.reject();
  }

  close(): void {
    this.turn.close();
  }

  /** Has the agent answer what was said, passing the reply on as it comes. */
  private async respond(
    said: string,
    agent: Agent,
    { history, profile, vocabulary }: ProfileStart,
    { audioSeconds, live, signal: ended, send }: Answering<ProfileServerMessage>,
  ): Promise<string> {
    const log = this.deps.log;
    send({ type: "heard", text: said });
    if (said === "") {
      // Nothing to answer: the agent is not asked.
      send({
        type: "done",
        reply: "",
        profile: null,
        add_terms: [],
        usage: usage(chargedAt(this.deps.prices, live), audioSeconds, 0, 0),
      });
      return "done";
    }
    const startedAt = Date.now();
    let firstReplyMs: number | undefined;
    const signal = AbortSignal.any([ended, AbortSignal.timeout(ANSWER_TIMEOUT_MS)]);
    try {
      const answer = await agent.answer(
        { history, said, profile, vocabulary },
        (text) => {
          firstReplyMs ??= Date.now() - startedAt;
          send({ type: "reply", text });
        },
        signal,
      );
      const used = usage(
        chargedAt(this.deps.prices, live),
        audioSeconds,
        answer.inputTokens,
        answer.outputTokens,
      );
      log.info("answered", {
        answer_ms: Date.now() - startedAt,
        first_reply_ms: firstReplyMs ?? -1,
        reply_chars: answer.reply.length,
        profile_changed: answer.profile !== undefined,
        terms: answer.profile?.terms.length ?? 0,
        add_terms: answer.addTerms.length,
      });
      log.info("used", { ...used });
      send({
        type: "done",
        reply: answer.reply,
        profile: answer.profile ? wireProfile(answer.profile) : null,
        add_terms: answer.addTerms,
        usage: used,
      });
      return "done";
    } catch (error) {
      if (ended.aborted) return "cancelled";
      log.error("answer failed", {
        answer_ms: Date.now() - startedAt,
        error: error instanceof Error ? error.message : String(error),
      });
      send({ type: "error", code: "agent_failed", message: "The agent did not answer" });
      return "agent_failed";
    }
  }
}
