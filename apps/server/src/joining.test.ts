import assert from "node:assert/strict";
import { test } from "node:test";
import { joinAfter } from "./joining.ts";

test("a dictation after a word or punctuation is spaced from it", () => {
  assert.equal(joinAfter("Thanks for the update", "and see you Friday."), " and see you Friday.");
  assert.equal(joinAfter("See you then.", "Bye."), " Bye.");
  assert.equal(joinAfter("Dear Ana,", "thanks."), " thanks.");
  assert.equal(joinAfter('She said "hi"', "and left."), " and left.");
});

test("a dictation after a space, a line break, or an opening is not spaced", () => {
  assert.equal(joinAfter("Thanks ", "and bye."), "and bye.");
  assert.equal(joinAfter("Hi Ana,\n", "Thanks."), "Thanks.");
  assert.equal(joinAfter("Call me (", "after five)."), "after five).");
  assert.equal(joinAfter('He said "', "hi."), "hi.");
  assert.equal(joinAfter('"', "hi."), "hi.");
  assert.equal(joinAfter("¿", "Vienes?"), "Vienes?");
});

test("punctuation that closes a phrase attaches to the text before it", () => {
  assert.equal(joinAfter("See you", ", then."), ", then.");
  assert.equal(joinAfter("Really", "?"), "?");
  assert.equal(joinAfter("(see above", ")"), ")");
});

test("scripts written without spaces are not spaced", () => {
  assert.equal(joinAfter("今日は", "晴れです。"), "晴れです。");
  assert.equal(joinAfter("Hello", "你好"), "你好");
  assert.equal(joinAfter("好。", "Hello"), "Hello");
});

test("without context or text, nothing is added", () => {
  assert.equal(joinAfter("", "Hello."), "Hello.");
  assert.equal(joinAfter("Hello", ""), "");
  assert.equal(joinAfter("a", "b"), " b");
});
