import assert from "node:assert/strict";
import { test } from "node:test";
import { createLogger, formatJson, formatPretty, type LogRecord, parseLine } from "./index.ts";

const record: LogRecord = {
  time: new Date(2026, 10, 11, 15, 4, 5, 6),
  level: "info",
  scope: "dictation",
  message: "segment refined",
  fields: { segment: 0, refine_ms: 302, note: "two words", skipped: undefined },
};

test("pretty lines align the level and scope and quote values with spaces", () => {
  assert.equal(
    formatPretty(record),
    '15:04:05.006 INFO  dictation   segment refined segment=0 refine_ms=302 note="two words"',
  );
});

test("JSON lines carry the fields beside the standard keys", () => {
  assert.deepEqual(JSON.parse(formatJson(record)), {
    time: record.time.toISOString(),
    level: "info",
    scope: "dictation",
    message: "segment refined",
    segment: 0,
    refine_ms: 302,
    note: "two words",
  });
});

test("a logger writes records at or above its level", () => {
  const lines: string[] = [];
  const log = createLogger({
    scope: "server",
    format: "json",
    level: "warn",
    write: (line) => lines.push(line),
  });
  log.info("ignored");
  log.warn("kept", { port: 8787 });
  assert.equal(lines.length, 1);
  assert.deepEqual(
    { ...JSON.parse(lines[0] ?? ""), time: undefined },
    { time: undefined, level: "warn", scope: "server", message: "kept", port: 8787 },
  );
});

test("a child logger changes the scope and adds fields to every record", () => {
  const lines: string[] = [];
  const log = createLogger({ scope: "server", format: "json", write: (line) => lines.push(line) });
  log.child({ scope: "dictation", fields: { dictation: 7 } }).info("started", { mode: "push" });
  const { scope, dictation, mode } = JSON.parse(lines[0] ?? "");
  assert.deepEqual({ scope, dictation, mode }, { scope: "dictation", dictation: 7, mode: "push" });
});

test("a line with fields is read back into its parts", () => {
  assert.deepEqual(parseLine('dictation failed reason=serverUnreachable note="a \\"b\\" c" n=3'), {
    message: "dictation failed",
    fields: { reason: "serverUnreachable", note: 'a "b" c', n: "3" },
  });
  assert.deepEqual(parseLine("shortcuts ready"), { message: "shortcuts ready", fields: {} });
});
