export class ConfigError extends Error {}

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
    throw new ConfigError(
      "OPENAI_API_KEY is not set. Copy apps/server/.env.example to apps/server/.env and add your key.",
    );
  }

  const port = Number(env.PORT ?? 8787);
  if (!Number.isInteger(port) || port < 0 || port > 65_535) {
    throw new ConfigError(`PORT must be a port number, got "${env.PORT}".`);
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
