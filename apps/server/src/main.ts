import { createLogger, type Fields } from "@voice/log";
import OpenAI from "openai";
import { type Config, ConfigError, loadConfig } from "./config.ts";
import { DICTATION_PATH } from "./protocol.ts";
import { createOpenAIRefiner } from "./refiner.ts";
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
      fatal("could not reach OpenAI", {
        error: error instanceof Error ? error.message : `${error}`,
      });
    }
  }
}

const { apiKey, host, port, transcribeModel, transcribeLanguages, refineModel, prices } = config();
const client = new OpenAI({ apiKey });
await checkOpenAI(client, [transcribeModel, refineModel]);

const server = createServer({
  createTranscriber: createOpenAITranscriber(client, {
    model: transcribeModel,
    languages: transcribeLanguages,
  }),
  createRefiner: createOpenAIRefiner(client, { model: refineModel }),
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
    transcribe: transcribeModel,
    refine: refineModel,
  });
});

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    log.info("stopping", { signal });
    server.close();
    server.closeAllConnections();
  });
}
