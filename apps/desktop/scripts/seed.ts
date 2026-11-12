// Fills the history and the statistics of the development app with samples, to work on
// the window without dictating first.
//
//   node scripts/seed.ts
//
// Some samples have a recording, spoken by a system voice, and one of them failed, to try
// playing and trying again. What the history already holds is kept, and running it again
// renews the samples. The statistics get sample figures for the days that have none: a day
// with figures is left as it is. The app reads its files when it starts, so a running app
// is quit first and opened again.

import { execFileSync, spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
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
  /** Whether the dictation failed, and can be tried again from its recording. */
  failed?: boolean;
}

/** The figures of a day as the app keeps them in `statistics.json`. */
interface Tally {
  dictations: number;
  words: number;
  /** How long the speaker talked, in seconds. */
  seconds: number;
  inputTokens: number;
  outputTokens: number;
  /** In US dollars. */
  cost: number;
}

/** What makes a sample more than text: a recording, spoken by a system voice, or a failure. */
interface Extra {
  /** The system voice that speaks the recording. Without one the sample has no recording. */
  voice?: string;
  /** What the recording says, when the sample has no text of its own. */
  spoken?: string;
  failed?: boolean;
}

/** A sample: how many days ago it was dictated, at what time, and the text that was typed. */
const samples: [daysAgo: number, time: string, text: string, extra?: Extra][] = [
  [
    0,
    "10:42",
    "Can you send me the draft before lunch? I'd like to read it once more.",
    { voice: "Samantha" },
  ],
  [
    0,
    "09:15",
    "Bom dia, pessoal. Hoje eu vou focar na janela do aplicativo: revisar o espaçamento da barra lateral, alinhar os títulos dos grupos com o texto das linhas e conferir o cursor em cada botão. Se sobrar tempo, começo a busca nas transcrições.",
    { voice: "Luciana" },
  ],
  [
    0,
    "08:03",
    "",
    {
      voice: "Samantha",
      spoken: "This one failed the first time. Open it and try again to see it transcribed.",
      failed: true,
    },
  ],
  [1, "17:48", "Fechado, a gente se fala amanhã às dez."],
  [
    1,
    "14:20",
    "Thanks for the review. I agree with the first two points and I've already pushed the fixes. On the third one, I'd rather keep the timeout where it is until we have numbers from a real recording, because lowering it now would hide the slow cases instead of showing them.",
    { voice: "Samantha" },
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

function isSample(id: string): boolean {
  return id.startsWith("5EED0000-");
}

/**
 * Speaks a text into a recording as the app keeps them: 16-bit mono PCM at 24 kHz in a WAV
 * file. Returns its length in seconds, or nothing when the voice is not installed.
 */
function record(text: string, voice: string, file: string): number | undefined {
  const spoken = spawnSync("say", ["-v", voice, "-o", file, "--data-format=LEI16@24000", text]);
  if (spoken.status !== 0 || !existsSync(file)) return undefined;
  return statSync(file).size / 2 / 24_000;
}

function sample(index: number, recordings: string): Transcription {
  const [daysAgo, time, text, extra = {}] = samples[index] ?? [0, "00:00", ""];
  const [hours = 0, minutes = 0] = time.split(":").map(Number);
  const date = new Date();
  date.setDate(date.getDate() - daysAgo);
  date.setHours(hours, minutes, 0, 0);
  // A sample dated later today would look like it came from the future.
  if (date > new Date()) date.setDate(date.getDate() - 1);
  const said = extra.spoken ?? text;
  const recorded =
    extra.voice && record(said, extra.voice, join(recordings, `${sampleId(index)}.wav`));
  return {
    id: sampleId(index),
    date: date.toISOString().replace(/\.\d+Z$/, "Z"),
    text,
    // About fourteen characters are spoken in a second.
    duration: recorded || Math.max(1, Math.round(said.length / 14)),
    ...(extra.failed && { failed: true }),
  };
}

/** The date of a day as the statistics name it, such as `2026-11-12`. */
function dayKey(daysAgo: number): string {
  const date = new Date();
  date.setDate(date.getDate() - daysAgo);
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/**
 * Sample figures for a day: a few dictations at a speaking pace, at OpenAI's prices. The
 * same on every run. One day in five has none.
 */
function sampleDay(daysAgo: number): Tally | undefined {
  let state = daysAgo * 7919 + 17;
  const pick = (bound: number) => {
    state = (state * 1103515245 + 12345) % 2147483648;
    return Math.floor((state / 2147483648) * bound);
  };
  if (pick(5) === 0) return undefined;
  const tally: Tally = {
    dictations: 1 + pick(9),
    words: 0,
    seconds: 0,
    inputTokens: 0,
    outputTokens: 0,
    cost: 0,
  };
  for (let dictation = 0; dictation < tally.dictations; dictation++) {
    const words = 8 + pick(120);
    tally.words += words;
    // Between 115 and 170 words a minute.
    tally.seconds += Math.round((words / (1.9 + pick(10) / 10)) * 10) / 10;
    // The refinement reads its instructions and the transcript, and writes the text.
    tally.inputTokens += 230 + Math.round(words * 1.6);
    tally.outputTokens += Math.round(words * 1.4);
  }
  tally.seconds = Math.round(tally.seconds * 10) / 10;
  const cost =
    (tally.seconds / 60) * 0.017 + (tally.inputTokens * 0.1 + tally.outputTokens * 0.5) / 1e6;
  tally.cost = Math.round(cost * 1e6) / 1e6;
  return tally;
}

/** How many days back the statistics get samples for. */
const SAMPLE_DAYS = 30;

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
  const recordings = join(directory, "recordings");

  // The app writes what it has in memory over the file, so it must not be running.
  const wasRunning = isRunning(identifier);
  if (wasRunning) {
    execFileSync("osascript", ["-e", `quit app id "${identifier}"`], { stdio: "ignore" });
    for (let tries = 0; isRunning(identifier) && tries < 100; tries++);
  }

  const kept: Transcription[] = existsSync(file)
    ? JSON.parse(readFileSync(file, "utf8")).transcriptions.filter(
        (transcription: Transcription) => !isSample(transcription.id),
      )
    : [];
  mkdirSync(recordings, { recursive: true });
  for (const recording of readdirSync(recordings)) {
    if (isSample(recording)) rmSync(join(recordings, recording));
  }
  const transcriptions = [...kept, ...samples.map((_, index) => sample(index, recordings))];
  writeFileSync(file, `${JSON.stringify({ transcriptions }, null, 2)}\n`);

  const statisticsFile = join(directory, "statistics.json");
  const days: Record<string, Tally> = existsSync(statisticsFile)
    ? JSON.parse(readFileSync(statisticsFile, "utf8")).days
    : {};
  let sampleDays = 0;
  for (let daysAgo = 0; daysAgo < SAMPLE_DAYS; daysAgo++) {
    const tally = sampleDay(daysAgo);
    if (!tally || days[dayKey(daysAgo)]) continue;
    days[dayKey(daysAgo)] = tally;
    sampleDays += 1;
  }
  writeFileSync(statisticsFile, `${JSON.stringify({ days }, null, 2)}\n`);

  log.info("seeded", {
    app: name,
    samples: samples.length,
    recordings: readdirSync(recordings).filter(isSample).length,
    kept: kept.length,
    statistics_days: sampleDays,
    file,
  });

  if (wasRunning) {
    execFileSync("open", ["-g", app]);
    log.info("reopened", { app: name });
  }
} catch (error) {
  log.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
