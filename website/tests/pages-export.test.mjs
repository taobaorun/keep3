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
  assert.match(html, /href="#first-launch-guide"/);
  assert.match(html, /当前版本未经过 Apple 公证/);
  assert.match(html, /按住 Control 点击 Keep3/);
  assert.match(html, /系统设置 → 隐私与安全性/);
  assert.match(html, /仍要打开/);
  assert.match(html, /https:\/\/support\.apple\.com\/102445/);
  assert.doesNotMatch(html, /RELEASE INTEGRITY/);
  assert.doesNotMatch(html, /查看 SHA-256 与源码标签/);
  assert.doesNotMatch(html, /查看全部正式版本与校验信息/);
  assert.match(html, /https:\/\/afdian\.com\/a\/taobaorun\/plan/);
  assert.doesNotMatch(html, /href="https:\/\/afdian\.com\/a\/taobaorun"/);
  assert.match(html, /支持它持续开发/);
  assert.doesNotMatch(html, /请我吃个披萨/);
  assert.match(html, /支持完全自愿/);
  assert.doesNotMatch(html, /weixin:\/\/|alipays:\/\/|<iframe\b/i);
  assert.doesNotMatch(html, /xattr|--no-quarantine/i);
});
