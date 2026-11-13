import { createLogger, type Fields } from "@voice/log";
import OpenAI from "openai";
import { type Config, ConfigError, loadConfig } from "./config.ts";
import { DICTATION_PATH, MEETING_PATH } from "./protocol.ts";
import { createOpenAIRefiner } from "./refiner.ts";
import { createOpenAIReviser } from "./reviser.ts";
import { createServer } from "./server.ts";
import { createOpenAITranscriber } from "./transcriber.ts";

const log = createLogger({ scope: "server" });

function fatal(message: string, fields?: Fields): never {
  log.error(message, fields);
  process.exit(1);
}

function config(): Config {
  try {
    return loadConfig();
  } catch (error) {
    if (error instanceof ConfigError) fatal(error.message, { hint: error.hint });
    throw error;
  }
}

/** Fails early when the key or a model is wrong, instead of on the first dictation. */
async function checkOpenAI(client: OpenAI, models: string[]): Promise<void> {
  for (const model of models) {
    try {
      await client.models.retrieve(model);
    } catch (error) {
      if (error instanceof OpenAI.AuthenticationError) {
        fatal("OpenAI rejected OPENAI_API_KEY", { hint: "check your key in apps/server/.env" });
      }
      if (error instanceof OpenAI.NotFoundError) {
        fatal("OpenAI model is not available to this key", { model });
      }
      // Without a network, as just after login, the server still starts: dictations work once
      // OpenAI can be reached.
      log.warn("could not reach OpenAI", {
        error: error instanceof Error ? error.message : `${error}`,
        hint: "the key and the models are not checked",
      });
      return;
    }
  }
}

const {
  apiKey,
  host,
  port,
  transcribeModel,
  transcribeLanguages,
  refineModel,
  prices,
  stopWithParent,
} = config();
const client = new OpenAI({ apiKey });
await checkOpenAI(client, [transcribeModel, refineModel]);

const server = createServer({
  createTranscriber: createOpenAITranscriber(client, {
    model: transcribeModel,
    languages: transcribeLanguages,
  }),
  createRefiner: createOpenAIRefiner(client, { model: refineModel }),
  createReviser: createOpenAIReviser(client, { model: refineModel }),
  prices,
  log,
});

server.on("error", (error: NodeJS.ErrnoException) => {
  if (error.code === "EADDRINUSE") fatal("port is in use", { port, hint: "set PORT" });
  fatal("server failed", { error: error.message });
});
server.listen(port, host, () => {
  log.info("listening", {
    url: `ws://${host}:${port}${DICTATION_PATH}`,
    meeting_url: `ws://${host}:${port}${MEETING_PATH}`,
    transcribe: transcribeModel,
    refine: refineModel,
  });
});

function stop(fields: Fields): void {
  log.info("stopping", fields);
  server.close();
  server.closeAllConnections();
  if (stopWithParent) process.stdin.destroy();
}

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => stop({ signal }));
}

// The program that started the server holds its standard input open. The input closes when
// that program ends, however it ends, and the server stops with it.
if (stopWithParent) {
  process.stdin.on("end", () => stop({ reason: "parent ended" }));
  process.stdin.resume();
}
