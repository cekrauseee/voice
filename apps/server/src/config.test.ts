import assert from "node:assert/strict";
import { test } from "node:test";
import { ConfigError, loadConfig } from "./config.ts";

test("the prices default to what OpenAI charges for the default models", () => {
  assert.deepEqual(loadConfig({ OPENAI_API_KEY: "key" }).prices, {
    transcribeMinute: 0.017,
    refineInput: 0.1,
    refineOutput: 0.5,
  });
});

test("the prices can be set", () => {
  const { prices } = loadConfig({
    OPENAI_API_KEY: "key",
    TRANSCRIBE_PRICE_PER_MINUTE: "0.006",
    REFINE_PRICE_PER_MILLION_INPUT: "0.2",
    REFINE_PRICE_PER_MILLION_OUTPUT: "1",
  });
  assert.deepEqual(prices, { transcribeMinute: 0.006, refineInput: 0.2, refineOutput: 1 });
});

test("the server stops with the program that started it only when asked to", () => {
  assert.equal(loadConfig({ OPENAI_API_KEY: "key" }).stopWithParent, false);
  assert.equal(loadConfig({ OPENAI_API_KEY: "key", STOP_WITH_PARENT: "1" }).stopWithParent, true);
});

test("a price that is not a number is a configuration problem", () => {
  assert.throws(
    () => loadConfig({ OPENAI_API_KEY: "key", REFINE_PRICE_PER_MILLION_INPUT: "cheap" }),
    ConfigError,
  );
});
