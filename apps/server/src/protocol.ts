/** Messages exchanged with the dictation client. The contract is docs/protocol.md. */

export const DICTATION_PATH = "/v1/dictation";

/** The WebSocket of a turn of the conversation about the speaker's profile. */
export const PROFILE_PATH = "/v1/profile";

/** Audio the client streams as binary frames: 16-bit little-endian mono PCM. */
export const SAMPLE_RATE = 24_000;
/** The audio is 16-bit mono at 24 kHz. */
export const BYTES_PER_SECOND = SAMPLE_RATE * 2;

export type ErrorCode = "bad_request" | "transcription_failed" | "unreachable" | "timeout";

/** What a dictation used, and what that costs. */
export interface Usage {
  /** Seconds of audio that were transcribed. */
  audio_seconds: number;
  /** Tokens the refinement read. */
  input_tokens: number;
  /** Tokens the refinement wrote. */
  output_tokens: number;
  /** The cost in US dollars, at the prices the server is configured with. */
  cost: number;
}

/** What OpenAI charges, in US dollars. */
export interface Prices {
  /** For a minute of audio transcribed once it is recorded. */
  transcribeMinute: number;
  /** For a minute of audio transcribed live, while the speaker talks. */
  liveTranscribeMinute: number;
  /** For a million tokens the refinement reads. */
  refineInput: number;
  /** For a million tokens the refinement writes. */
  refineOutput: number;
}

export function usage(
  prices: Prices,
  audioSeconds: number,
  inputTokens: number,
  outputTokens: number,
): Usage {
  const cost =
    (audioSeconds / 60) * prices.transcribeMinute +
    (inputTokens * prices.refineInput + outputTokens * prices.refineOutput) / 1_000_000;
  return {
    audio_seconds: Math.round(audioSeconds * 10) / 10,
    input_tokens: inputTokens,
    output_tokens: outputTokens,
    cost: Math.round(cost * 1_000_000) / 1_000_000,
  };
}

export type ServerMessage =
  | { type: "ready" }
  | { type: "delta"; text: string }
  | { type: "done"; text: string; usage: Usage }
  | { type: "error"; code: ErrorCode; message: string };

/** What the client opens a dictation with. */
export interface Start {
  /** How the speaker wants the text written. */
  instructions: string;
  /** The language to write the text in. Empty to keep the speaker's. */
  translateTo: string;
  /** Names and terms the speaker uses, as they spell them. */
  vocabulary: string[];
  /** The text before the cursor in the field the dictation goes into. */
  context: string;
  /** Whether the audio is transcribed while the speaker talks, with the text heard sent as it comes. */
  live: boolean;
  /** What the speaker's recordings are like, for the transcription. */
  transcriptionPrompt: string;
  /** The languages the speaker speaks, as ISO 639-1 codes. */
  languages: string[];
}

export type ClientMessage = ({ type: "start" } & Start) | { type: "stop" };

export function parseClientMessage(raw: string): ClientMessage | undefined {
  const value = parseJson(raw);
  if (value === undefined) return undefined;
  if (value.type === "stop") return { type: "stop" };
  if (value.type === "start") {
    const instructions = value.instructions ?? "";
    const translateTo = value.translate_to ?? "";
    const vocabulary = value.vocabulary ?? [];
    const context = value.context ?? "";
    const live = value.live ?? false;
    const transcriptionPrompt = value.transcription_prompt ?? "";
    const languages = value.languages ?? [];
    if (
      typeof instructions === "string" &&
      typeof translateTo === "string" &&
      isStrings(vocabulary) &&
      typeof context === "string" &&
      typeof live === "boolean" &&
      typeof transcriptionPrompt === "string" &&
      isStrings(languages)
    ) {
      return {
        type: "start",
        instructions,
        translateTo,
        vocabulary,
        context,
        live,
        transcriptionPrompt,
        languages,
      };
    }
  }
  return undefined;
}

/**
 * What the models are told about a speaker, as the app keeps it: the instructions, the
 * description of their recordings, and the languages go with every dictation, and the terms
 * are suggested for their dictionary.
 */
export interface Profile {
  /** How the speaker wants their text written, for the refinement. */
  instructions: string;
  /** What the speaker's recordings are like, for the transcription. */
  transcriptionPrompt: string;
  /** The languages the speaker speaks, as ISO 639-1 codes. */
  languages: string[];
  /** Names and terms suggested for the speaker's dictionary, not yet added. */
  terms: string[];
}

/** A message of the conversation about the speaker's profile. */
export interface ConversationEntry {
  /** `user` is the speaker, `assistant` the agent. */
  role: "user" | "assistant";
  text: string;
  /** The profile the agent wrote with this message, if it changed it. */
  profile?: Profile;
}

/** The profile as the protocol carries it. */
export interface WireProfile {
  instructions: string;
  transcription_prompt: string;
  languages: string[];
  terms: string[];
}

export function wireProfile(profile: Profile): WireProfile {
  return {
    instructions: profile.instructions,
    transcription_prompt: profile.transcriptionPrompt,
    languages: profile.languages,
    terms: profile.terms,
  };
}

/** What the client opens a turn of the profile conversation with. */
export interface ProfileStart {
  /** The conversation so far, oldest first. */
  history: ConversationEntry[];
  /** The speaker's profile as it is now. */
  profile: Profile;
  /** The speaker's dictionary. */
  vocabulary: string[];
}

export type ProfileClientMessage = ({ type: "start" } & ProfileStart) | { type: "stop" };

export type ProfileErrorCode = ErrorCode | "agent_failed";

/** A message of a turn of the profile conversation, to the client. */
export type ProfileServerMessage =
  | { type: "ready" }
  | { type: "delta"; text: string }
  | { type: "heard"; text: string }
  | { type: "reply"; text: string }
  | {
      type: "done";
      reply: string;
      profile: WireProfile | null;
      add_terms: string[];
      usage: Usage;
    }
  | { type: "error"; code: ProfileErrorCode; message: string };

const EMPTY_PROFILE: Profile = {
  instructions: "",
  transcriptionPrompt: "",
  languages: [],
  terms: [],
};

/** Reads a message of a turn of the profile conversation. Undefined when it is not one. */
export function parseProfileClientMessage(raw: string): ProfileClientMessage | undefined {
  const value = parseJson(raw);
  if (value === undefined) return undefined;
  if (value.type === "stop") return { type: "stop" };
  if (value.type !== "start") return undefined;
  const vocabulary = value.vocabulary ?? [];
  const rawHistory = value.history ?? [];
  if (!isStrings(vocabulary) || !Array.isArray(rawHistory)) return undefined;
  const profile = value.profile === undefined ? EMPTY_PROFILE : readProfile(value.profile);
  if (!profile) return undefined;
  const history: ConversationEntry[] = [];
  for (const raw of rawHistory) {
    if (typeof raw !== "object" || raw === null) return undefined;
    const { role, text, profile: written } = raw as Record<string, unknown>;
    if ((role !== "user" && role !== "assistant") || typeof text !== "string") return undefined;
    if (written === undefined || written === null) {
      history.push({ role, text });
      continue;
    }
    const entryProfile = readProfile(written);
    if (!entryProfile) return undefined;
    history.push({ role, text, profile: entryProfile });
  }
  return { type: "start", history, profile, vocabulary };
}

function readProfile(value: unknown): Profile | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return undefined;
  const fields = value as Record<string, unknown>;
  const instructions = fields.instructions ?? "";
  const transcriptionPrompt = fields.transcription_prompt ?? "";
  const languages = fields.languages ?? [];
  const terms = fields.terms ?? [];
  if (
    typeof instructions !== "string" ||
    typeof transcriptionPrompt !== "string" ||
    !isStrings(languages) ||
    !isStrings(terms)
  ) {
    return undefined;
  }
  return { instructions, transcriptionPrompt, languages, terms };
}

function isStrings(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}

function parseJson(raw: string): Record<string, unknown> | undefined {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return undefined;
  }
  if (typeof value !== "object" || value === null || !("type" in value)) return undefined;
  return value as Record<string, unknown>;
}
