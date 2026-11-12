// Fills the history of the development app with sample transcriptions, to work on the
// window without dictating first.
//
//   node scripts/seed.ts
//
// What the history already holds is kept, and running it again renews the samples. The
// app reads its history when it starts, so a running app is quit first and opened again.

import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createLogger } from "@voice/log";
import { variant } from "./variants.ts";

/** A transcription as the app keeps it in `history.json`. */
interface Transcription {
  id: string;
  /** ISO 8601, without fractions of a second. */
  date: string;
  text: string;
  /** The length of the recording, in seconds. */
  duration: number;
}

/** A sample: how many days ago it was dictated, at what time, and what was said. */
const samples: [daysAgo: number, time: string, text: string][] = [
  [0, "10:42", "Can you send me the draft before lunch? I'd like to read it once more."],
  [
    0,
    "09:15",
    "Bom dia, pessoal. Hoje eu vou focar na janela do aplicativo: revisar o espaçamento da barra lateral, alinhar os títulos dos grupos com o texto das linhas e conferir o cursor em cada botão. Se sobrar tempo, começo a busca nas transcrições.",
  ],
  [0, "08:03", "Remind me to renew the developer certificate on Friday."],
  [1, "17:48", "Fechado, a gente se fala amanhã às dez."],
  [
    1,
    "14:20",
    "Thanks for the review. I agree with the first two points and I've already pushed the fixes. On the third one, I'd rather keep the timeout where it is until we have numbers from a real recording, because lowering it now would hide the slow cases instead of showing them.",
  ],
  [1, "11:06", "Add milk, coffee, and oats to the shopping list."],
  [2, "16:31", "O texto chega cerca de dois segundos depois de soltar a tecla."],
  [
    2,
    "09:54",
    "Notes from the call: the release goes out on Thursday, the server first and the app right after. Ana updates the documentation, and I write the announcement. We meet again on Monday to look at the first feedback.",
  ],
  [4, "18:12", "Não esquece de pausar a música antes de gravar."],
  [4, "13:37", "Let's move the standup to half past nine."],
  [
    6,
    "10:25",
    "Oi, tudo bem? Estou escrevendo para confirmar a reunião de quinta-feira. Podemos manter o horário das quinze horas, e eu levo a apresentação com os números do trimestre. Se precisar mudar alguma coisa, me avisa até amanhã.",
  ],
  [6, "08:47", "What's the weather like in Lisbon this weekend?"],
  [9, "15:09", "The waveform should follow the voice from the center outward."],
  [
    9,
    "11:52",
    "Ideia para depois: guardar o áudio de cada ditado na versão de desenvolvimento, para repetir a mesma gravação quando o prompt mudar e comparar os resultados lado a lado.",
  ],
  [13, "19:20", "Call the dentist and ask for an appointment next week."],
  [13, "09:02", "Primeiro teste do ditado. Funcionou."],
];

/** The identifier of a sample, the same on every run, so samples replace themselves. */
function sampleId(index: number): string {
  return `5EED0000-0000-4000-8000-${String(index).padStart(12, "0")}`;
}

function isSample(transcription: Transcription): boolean {
  return transcription.id.startsWith("5EED0000-");
}

function sample(index: number): Transcription {
  const [daysAgo, time, text] = samples[index] ?? [0, "00:00", ""];
  const [hours = 0, minutes = 0] = time.split(":").map(Number);
  const date = new Date();
  date.setDate(date.getDate() - daysAgo);
  date.setHours(hours, minutes, 0, 0);
  // A sample dated later today would look like it came from the future.
  if (date > new Date()) date.setDate(date.getDate() - 1);
  return {
    id: sampleId(index),
    date: date.toISOString().replace(/\.\d+Z$/, "Z"),
    text,
    // About fourteen characters are spoken in a second.
    duration: Math.max(1, Math.round(text.length / 14)),
  };
}

function isRunning(identifier: string): boolean {
  const answer = spawnSync("osascript", ["-e", `application id "${identifier}" is running`], {
    encoding: "utf8",
  });
  return answer.stdout.trim() === "true";
}

const log = createLogger({ scope: "seed" });

try {
  const { app, identifier, name } = variant("development");
  const directory = join(homedir(), "Library", "Application Support", identifier);
  const file = join(directory, "history.json");

  // The app writes what it has in memory over the file, so it must not be running.
  const wasRunning = isRunning(identifier);
  if (wasRunning) {
    execFileSync("osascript", ["-e", `quit app id "${identifier}"`], { stdio: "ignore" });
    for (let tries = 0; isRunning(identifier) && tries < 100; tries++);
  }

  const kept: Transcription[] = existsSync(file)
    ? JSON.parse(readFileSync(file, "utf8")).transcriptions.filter(
        (transcription: Transcription) => !isSample(transcription),
      )
    : [];
  const transcriptions = [...kept, ...samples.map((_, index) => sample(index))];
  mkdirSync(directory, { recursive: true });
  writeFileSync(file, `${JSON.stringify({ transcriptions }, null, 2)}\n`);
  log.info("seeded", { app: name, samples: samples.length, kept: kept.length, file });

  if (wasRunning) {
    execFileSync("open", ["-g", app]);
    log.info("reopened", { app: name });
  }
} catch (error) {
  log.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
