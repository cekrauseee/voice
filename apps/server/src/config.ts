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
  transcribeModel: string;
  transcribeLanguages: string[];
  refineModel: string;
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

  return {
    apiKey,
    host: env.HOST || "127.0.0.1",
    port,
    transcribeModel: env.TRANSCRIBE_MODEL || "gpt-live-transcribe",
    transcribeLanguages: (env.TRANSCRIBE_LANGUAGES ?? "")
      .split(",")
      .map((language) => language.trim())
      .filter((language) => language !== ""),
    refineModel: env.REFINE_MODEL || "gpt-6-luna",
  };
}
