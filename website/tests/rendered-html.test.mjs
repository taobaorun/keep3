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
  assert.match(html, /本地优先/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
});
