import { styleText } from "node:util";

export type Level = "debug" | "info" | "warn" | "error";
export type Format = "pretty" | "json";
export type Fields = Record<string, string | number | boolean | undefined>;

export interface LogRecord {
  time: Date;
  level: Level;
  /** The component the record is about, such as `server` or `dictation`. */
  scope: string;
  /** What happened, as a short lowercase phrase. Details go in the fields. */
  message: string;
  fields: Fields;
}

export interface Logger {
  debug(message: string, fields?: Fields): void;
  info(message: string, fields?: Fields): void;
  warn(message: string, fields?: Fields): void;
  error(message: string, fields?: Fields): void;
  /** A logger with another scope, or with fields added to every record. */
  child(options: { scope?: string; fields?: Fields }): Logger;
}

export interface LoggerOptions {
  scope: string;
  /** Defaults to `LOG_FORMAT`, then to pretty on a terminal and JSON elsewhere. */
  format?: Format;
  /** The lowest level written. Defaults to `LOG_LEVEL`, then to `info`. */
  level?: Level;
  /** Where lines go. Defaults to standard output. */
  write?(line: string): void;
}

const LEVELS: Level[] = ["debug", "info", "warn", "error"];
const SCOPE_WIDTH = 11;

export function createLogger(options: LoggerOptions): Logger {
  const format = options.format ?? formatFromEnvironment();
  const threshold = LEVELS.indexOf(options.level ?? levelFromEnvironment());
  const write = options.write ?? ((line) => process.stdout.write(`${line}\n`));
  const render = format === "json" ? formatJson : formatPretty;

  const logger = (scope: string, bound: Fields): Logger => {
    const log = (level: Level) => (message: string, fields?: Fields) => {
      if (LEVELS.indexOf(level) < threshold) return;
      write(render({ time: new Date(), level, scope, message, fields: { ...bound, ...fields } }));
    };
    return {
      debug: log("debug"),
      info: log("info"),
      warn: log("warn"),
      error: log("error"),
      child: (child) => logger(child.scope ?? scope, { ...bound, ...child.fields }),
    };
  };
  return logger(options.scope, {});
}

function formatFromEnvironment(): Format {
  const format = process.env.LOG_FORMAT;
  if (format === "pretty" || format === "json") return format;
  return process.stdout.isTTY ? "pretty" : "json";
}

function levelFromEnvironment(): Level {
  const level = process.env.LOG_LEVEL as Level;
  return LEVELS.includes(level) ? level : "info";
}

/** One JSON object per line, for machines. */
export function formatJson({ time, level, scope, message, fields }: LogRecord): string {
  return JSON.stringify({ time: time.toISOString(), level, scope, message, ...fields });
}

const LEVEL_STYLE = { debug: "dim", info: "cyan", warn: "yellow", error: "red" } as const;

/** `15:04:05.123 INFO  scope       message key=value`, for people. Colored on a terminal. */
export function formatPretty({ time, level, scope, message, fields }: LogRecord): string {
  const clock = [time.getHours(), time.getMinutes(), time.getSeconds()]
    .map((part) => String(part).padStart(2, "0"))
    .join(":");
  const milliseconds = String(time.getMilliseconds()).padStart(3, "0");
  const details = Object.entries(fields)
    .filter(([, value]) => value !== undefined)
    .map(([key, value]) => `${styleText("dim", `${key}=`)}${formatValue(value)}`);
  return [
    styleText("dim", `${clock}.${milliseconds}`),
    styleText(LEVEL_STYLE[level], level.toUpperCase().padEnd(5)),
    styleText("bold", scope.padEnd(SCOPE_WIDTH)),
    level === "error" ? styleText("red", message) : message,
    ...details,
  ].join(" ");
}

function formatValue(value: Fields[string]): string {
  const text = String(value);
  return /^[^\s"=]+$/.test(text) ? text : JSON.stringify(text);
}

/**
 * Reads a line written as `message key=value key="quoted value"` back into its parts.
 * This is how the desktop app writes its records to the system log.
 */
export function parseLine(line: string): { message: string; fields: Fields } {
  const fields: Fields = {};
  const pattern = /\s([A-Za-z_][\w.]*)=("(?:[^"\\]|\\.)*"|[^\s"]*)/g;
  const first = pattern.exec(line);
  if (!first) return { message: line, fields };
  for (let match: RegExpExecArray | null = first; match; match = pattern.exec(line)) {
    const [, key, value] = match as unknown as [string, string, string];
    fields[key] = value.startsWith('"') ? (JSON.parse(value) as string) : value;
  }
  return { message: line.slice(0, first.index), fields };
}
