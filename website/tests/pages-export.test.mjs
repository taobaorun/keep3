import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("exports the product site for the /keep3 GitHub Pages path", async () => {
  const html = await readFile(new URL("../out/index.html", import.meta.url), "utf8");

  assert.match(html, /href="\/keep3\/_next\//);
  assert.match(html, /src="\/keep3\/_next\//);
  assert.match(html, /src="\/keep3\/keep3-app-icon\.png"/);
  assert.match(html, /href="#download"/);
  assert.match(html, /href="#support"/);
  assert.match(html, /https:\/\/github\.com\/taobaorun\/keep3\/releases/);
  assert.match(html, /https:\/\/afdian\.com\/a\/taobaorun\/plan/);
  assert.doesNotMatch(html, /href="https:\/\/afdian\.com\/a\/taobaorun"/);
  assert.match(html, /支持它持续开发/);
  assert.doesNotMatch(html, /请我吃个披萨/);
  assert.match(html, /支持完全自愿/);
  assert.doesNotMatch(html, /weixin:\/\/|alipays:\/\/|<iframe\b/i);
});
