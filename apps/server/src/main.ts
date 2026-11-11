import OpenAI from "openai";
import { type Config, ConfigError, loadConfig } from "./config.ts";
import { DICTATION_PATH } from "./protocol.ts";
import { createOpenAIRefiner } from "./refiner.ts";
import { createServer } from "./server.ts";
import { createOpenAITranscriber } from "./transcriber.ts";

function fatal(message: string): never {
  console.error(`error: ${message}`);
  process.exit(1);
}

function config(): Config {
  try {
    return loadConfig();
  } catch (error) {
    if (error instanceof ConfigError) fatal(error.message);
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
        fatal("OpenAI rejected OPENAI_API_KEY. Check your key in apps/server/.env.");
      }
      if (error instanceof OpenAI.NotFoundError) {
        fatal(`OpenAI model "${model}" is not available to this key.`);
      }
      fatal(`Could not reach OpenAI: ${error instanceof Error ? error.message : error}`);
    }
  }
}

const { apiKey, host, port, transcribeModel, transcribeLanguages, refineModel } = config();
const client = new OpenAI({ apiKey });
await checkOpenAI(client, [transcribeModel, refineModel]);

const server = createServer({
  createTranscriber: createOpenAITranscriber(client, {
    model: transcribeModel,
    languages: transcribeLanguages,
  }),
  refiner: createOpenAIRefiner(client, refineModel),
  log: (message) => console.log(message),
});

server.on("error", (error: NodeJS.ErrnoException) => {
  fatal(error.code === "EADDRINUSE" ? `Port ${port} is in use. Set PORT.` : error.message);
});
server.listen(port, host, () => {
  console.log(`ready: ws://${host}:${port}${DICTATION_PATH}`);
});

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    server.close();
    server.closeAllConnections();
  });
}
