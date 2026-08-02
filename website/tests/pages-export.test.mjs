import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("exports the product site for the /keep3 GitHub Pages path", async () => {
  const html = await readFile(new URL("../out/index.html", import.meta.url), "utf8");

  assert.match(html, /href="\/keep3\/_next\//);
  assert.match(html, /src="\/keep3\/_next\//);
  assert.match(html, /src="\/keep3\/keep3-app-icon\.png"/);
  assert.match(html, /href="#download"/);
  assert.match(html, /https:\/\/github\.com\/taobaorun\/keep3\/releases/);
});
