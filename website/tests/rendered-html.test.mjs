import assert from "node:assert/strict";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the Keep3 product site", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<html lang="zh-CN">/i);
  assert.match(html, /<title>Keep3 — 把最重要的三件事，留在视线里<\/title>/i);
  assert.match(html, /Keep three things in sight\./i);
  assert.match(html, /一个位置，守住你的工作上下文。/);
  assert.match(html, /三件重点/);
  assert.match(html, /媒体/);
  assert.match(html, /日历/);
  assert.match(html, /从一行提示，到完整控制。/);
  assert.match(html, /src="\/product-gallery\/priority-compact\.webp"/);
  assert.match(html, /src="\/product-gallery\/priority-expanded\.webp"/);
  assert.match(html, /src="\/product-gallery\/media-compact\.webp"/);
  assert.match(html, /src="\/product-gallery\/media-expanded\.webp"/);
  assert.match(html, /alt="Keep3 紧凑重点界面，显示第一项重点 AD-Harness"/);
  assert.match(html, /alt="Keep3 展开媒体界面，显示李健八月照相馆的封面、进度和播放控制"/);
  assert.match(html, /本地优先/);
  assert.match(html, /href="#download"/);
  assert.match(html, /href="#support"/);
  assert.match(html, /直接下载 DMG/);
  assert.match(html, /Homebrew 安装/);
  assert.match(html, /href="#first-launch-guide"/);
  assert.match(html, /当前版本未经过 Apple 公证/);
  assert.match(html, /按住 Control 点击 Keep3/);
  assert.match(html, /系统设置 → 隐私与安全性/);
  assert.match(html, /仍要打开/);
  assert.match(
    html,
    /href="https:\/\/support\.apple\.com\/102445"[^>]+target="_blank"[^>]+rel="noreferrer"/,
  );
  assert.match(html, /brew install --cask taobaorun\/keep3\/keep3/);
  assert.match(html, /https:\/\/github\.com\/taobaorun\/keep3\/releases/);
  assert.match(html, /macOS 14 或更高版本/);
  assert.match(html, /Apple silicon/);
  assert.doesNotMatch(html, /RELEASE INTEGRITY/);
  assert.doesNotMatch(html, /查看 SHA-256 与源码标签/);
  assert.doesNotMatch(html, /查看全部正式版本与校验信息/);
  assert.match(html, /支持它持续开发/);
  assert.match(html, /在爱发电支持 Keep3/);
  assert.doesNotMatch(html, /请我吃个披萨/);
  assert.doesNotMatch(html, /付款方式|支付与隐私|微信支付|支付宝/);
  assert.match(html, /支持完全自愿/);
  assert.match(html, /不会改变 Keep3 的下载、更新或任何功能/);
  assert.match(
    html,
    /<a[^>]+href="https:\/\/afdian\.com\/a\/taobaorun\/plan"[^>]+target="_blank"[^>]+rel="noreferrer"/,
  );
  assert.doesNotMatch(html, /href="https:\/\/afdian\.com\/a\/taobaorun"/);
  assert.doesNotMatch(html, /weixin:\/\/|alipays:\/\/|<iframe\b/i);
  assert.doesNotMatch(html, /xattr|--no-quarantine/i);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
});
