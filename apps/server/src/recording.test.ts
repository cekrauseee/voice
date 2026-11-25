import assert from "node:assert/strict";
import { test } from "node:test";
import { BYTES_PER_SECOND } from "./protocol.ts";
import { splitAtPauses } from "./recording.ts";

/** Speech-like audio: loud everywhere, but silent over the given seconds. */
function speech(seconds: number, silent: [from: number, to: number][] = []): Buffer {
  const pcm = Buffer.alloc(seconds * BYTES_PER_SECOND);
  for (let offset = 0; offset < pcm.length; offset += 2) {
    const second = offset / BYTES_PER_SECOND;
    const quiet = silent.some(([from, to]) => second >= from && second < to);
    pcm.writeInt16LE(quiet ? 0 : offset % 4 === 0 ? 8000 : -8000, offset);
  }
  return pcm;
}

test("a recording that fits is one part", () => {
  const pcm = speech(2);
  assert.deepEqual(splitAtPauses(pcm, 2 * BYTES_PER_SECOND, BYTES_PER_SECOND), [pcm]);
});

test("a long recording is cut at the pause before the limit", () => {
  const pcm = speech(5, [[2.3, 2.5]]);
  const parts = splitAtPauses(pcm, 3 * BYTES_PER_SECOND, BYTES_PER_SECOND);
  assert.equal(parts.length, 2);
  const cut = (parts[0]?.length ?? 0) / BYTES_PER_SECOND;
  assert.ok(cut > 2.3 && cut < 2.5, `cut at ${cut} s`);
  assert.deepEqual(Buffer.concat(parts), pcm);
});

test("every part fits, starts on a sample, and the parts make the whole", () => {
  const pcm = speech(10, [
    [1.2, 1.3],
    [7.05, 7.2],
  ]);
  const parts = splitAtPauses(pcm, 3 * BYTES_PER_SECOND, BYTES_PER_SECOND);
  for (const part of parts) {
    assert.ok(part.length <= 3 * BYTES_PER_SECOND);
    assert.equal(part.length % 2, 0);
  }
  assert.deepEqual(Buffer.concat(parts), pcm);
});

test("a part is never cut in its first half, even at a pause there", () => {
  const pcm = speech(4, [[0.2, 0.4]]);
  const parts = splitAtPauses(pcm, 2 * BYTES_PER_SECOND, 2 * BYTES_PER_SECOND);
  assert.ok((parts[0]?.length ?? 0) >= BYTES_PER_SECOND);
});
