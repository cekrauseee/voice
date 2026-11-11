import assert from "node:assert/strict";
import { test } from "node:test";
import { mergeEnv } from "./env.ts";

const example = `# Required.
KEY=

# Optional. Defaults shown.
# HOST=127.0.0.1
# PORT=8787
`;

test("a missing file is created from the example", () => {
  assert.deepEqual(mergeEnv(example, ""), { content: example, added: ["KEY", "HOST", "PORT"] });
});

test("a complete file is left alone", () => {
  const current = "PORT=9000\nKEY=secret\n# HOST=0.0.0.0\n";
  assert.deepEqual(mergeEnv(example, current), { content: current, added: [] });
});

test("a new block is added with its comments, and existing values are kept", () => {
  const current = "KEY=secret";
  assert.deepEqual(mergeEnv(example, current), {
    content: "KEY=secret\n\n# Optional. Defaults shown.\n# HOST=127.0.0.1\n# PORT=8787\n",
    added: ["HOST", "PORT"],
  });
});

test("a new variable in a known block is added on its own", () => {
  const current = "KEY=secret\nHOST=0.0.0.0\n";
  assert.deepEqual(mergeEnv(example, current), {
    content: "KEY=secret\nHOST=0.0.0.0\n\n# PORT=8787\n",
    added: ["PORT"],
  });
});
