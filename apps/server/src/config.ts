import type { Prices } from "./protocol.ts";
import type { ReasoningEffort } from "./responses.ts";

/** A configuration problem, with what to do about it. */
export class ConfigError extends Error {
  readonly hint: string;

  constructor(message: string, hint: string) {
    super(message);
    this.hint = hint;
  }
}

export interface Config {
  apiKey: string;
  host: string;
  port: number;
  /** The model that transcribes a recording once the speaker stops. */
  transcribeModel: string;
  /** The model that transcribes while the speaker talks. */
  liveTranscribeModel: string;
  transcribeLanguages: string[];
  refineModel: string;
  /** How much the refinement model reasons before it answers in the profile conversation. */
  profileReasoning: ReasoningEffort;
  prices: Prices;
  /** Stop when the program that started the server ends, such as the app. */
  stopWithParent: boolean;
}

const EFFORTS: readonly ReasoningEffort[] = ["none", "low", "medium", "high"];

function reasoning(value: string | undefined): ReasoningEffort {
  if (!value) return "none";
  const effort = EFFORTS.find((effort) => effort === value);
  if (!effort) {
    throw new ConfigError(
      `PROFILE_REASONING is not a reasoning effort: ${value}`,
      `set it to ${EFFORTS.join(", ")}`,
    );
  }
  return effort;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const apiKey = env.OPENAI_API_KEY?.trim();
  if (!apiKey) {
    throw new ConfigError("OPENAI_API_KEY is not set", "add your key to apps/server/.env");
  }

  const port = Number(env.PORT ?? 8787);
  if (!Number.isInteger(port) || port < 0 || port > 65_535) {
    throw new ConfigError(`PORT is not a port number: ${env.PORT}`, "set PORT to 0-65535");
  }

  const price = (name: string, fallback: number) => {
    const value = Number(env[name] ?? fallback);
    if (!Number.isFinite(value) || value < 0) {
      throw new ConfigError(`${name} is not a price: ${env[name]}`, "set it to US dollars");
    }
    return value;
  };

  return {
    apiKey,
    host: env.HOST || "127.0.0.1",
    port,
    transcribeModel: env.TRANSCRIBE_MODEL || "gpt-transcribe",
    liveTranscribeModel: env.LIVE_TRANSCRIBE_MODEL || "gpt-live-transcribe",
    transcribeLanguages: (env.TRANSCRIBE_LANGUAGES ?? "")
      .split(",")
      .map((language) => language.trim())
      .filter((language) => language !== ""),
    refineModel: env.REFINE_MODEL || "gpt-6-luna",
    profileReasoning: reasoning(env.PROFILE_REASONING),
    // OpenAI's prices for the default models, as published in November 2026.
    prices: {
      transcribeMinute: price("TRANSCRIBE_PRICE_PER_MINUTE", 0.0045),
      liveTranscribeMinute: price("LIVE_TRANSCRIBE_PRICE_PER_MINUTE", 0.017),
      refineInput: price("REFINE_PRICE_PER_MILLION_INPUT", 0.1),
      refineOutput: price("REFINE_PRICE_PER_MILLION_OUTPUT", 0.5),
    },
    stopWithParent: env.STOP_WITH_PARENT === "1",
  };
}
