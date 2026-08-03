"use client";

import { useEffect, useState } from "react";
import {
  fetchVerifiedRelease,
  releaseChannel,
} from "../lib/release-channel.mjs";
import {
  InstallNotice,
  UnsignedFirstLaunchGuide,
} from "./UnsignedFirstLaunchGuide";

type ReleaseInfo = {
  version: string;
  build: number;
  trustState: "unsigned" | "developer-id";
  artifactUrl: string;
  fileName: string;
  size: number;
};

type DiscoveryState =
  | { kind: "loading" }
  | { kind: "ready"; release: ReleaseInfo }
  | { kind: "unavailable" };

function formatSize(bytes: number) {
  return `${(bytes / 1_000_000).toFixed(1)} MB`;
}

export function ProductDownload() {
  const [discovery, setDiscovery] = useState<DiscoveryState>({ kind: "loading" });
  const [copyState, setCopyState] = useState<"idle" | "copied" | "failed">(
    "idle",
  );

  useEffect(() => {
    const controller = new AbortController();

    fetchVerifiedRelease({ signal: controller.signal })
      .then((release: ReleaseInfo) => {
        setDiscovery({ kind: "ready", release });
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        setDiscovery({ kind: "unavailable" });
      });

    return () => controller.abort();
  }, []);

  useEffect(() => {
    if (window.location.hash !== "#first-launch-guide") return;

    const frame = window.requestAnimationFrame(() => {
      document
        .getElementById("first-launch-guide")
        ?.scrollIntoView({ block: "start" });
    });

    return () => window.cancelAnimationFrame(frame);
  }, []);

  async function copyHomebrewCommand() {
    try {
      await navigator.clipboard.writeText(releaseChannel.homebrewCommand);
      setCopyState("copied");
    } catch {
      setCopyState("failed");
    }
  }

  const release = discovery.kind === "ready" ? discovery.release : null;
  const downloadUrl = release?.artifactUrl ?? releaseChannel.fallbackUrl;
  const downloadLabel = release ? "下载 Keep3 DMG" : "前往 GitHub Releases";
  const showUnsignedGuide = release?.trustState !== "developer-id";

  return (
    <section className="download-section" id="download" aria-labelledby="download-title">
      <div className="download-heading">
        <div>
          <p className="eyebrow eyebrow-light">DOWNLOAD KEEP3</p>
          <h2 id="download-title">选一种方式，把 Keep3 放进你的 Mac。</h2>
        </div>
        <div className="release-discovery" aria-live="polite">
          <span className={`release-indicator release-indicator-${discovery.kind}`} />
          {discovery.kind === "loading" && "正在验证正式版本…"}
          {discovery.kind === "ready" &&
            `已验证正式版 ${release?.version} (${release?.build})`}
          {discovery.kind === "unavailable" && "自动校验暂时不可用"}
        </div>
      </div>

      <div className="download-options">
        <article className="download-card download-card-primary">
          <div className="download-card-topline">
            <span>推荐</span>
            <span>01</span>
          </div>
          <h3>直接下载 DMG</h3>
          <p>
            下载磁盘映像，将 Keep3 拖入“应用程序”。适合第一次安装，过程最直观。
          </p>
          {showUnsignedGuide && <InstallNotice method="dmg" />}
          <a className="download-button" href={downloadUrl}>
            {downloadLabel}
            <span aria-hidden="true">↓</span>
          </a>
          <div className="download-meta">
            <span>{release?.fileName ?? "由 GitHub Releases 提供"}</span>
            <span>{release ? formatSize(release.size) : "macOS 14+"}</span>
          </div>
        </article>

        <article className="download-card download-card-terminal">
          <div className="download-card-topline">
            <span>命令行</span>
            <span>02</span>
          </div>
          <h3>Homebrew 安装</h3>
          <p>
            已经使用 Homebrew？在终端运行官方 tap 命令，以后也可以通过 Homebrew 升级。
          </p>
          {showUnsignedGuide && <InstallNotice method="homebrew" />}
          <div className="command-row">
            <code>{releaseChannel.homebrewCommand}</code>
            <button type="button" onClick={copyHomebrewCommand}>
              {copyState === "copied" ? "已复制" : "复制"}
            </button>
          </div>
          <p className="copy-feedback" role="status">
            {copyState === "failed" ? "复制失败，请手动选择命令。" : ""}
          </p>
          <div className="download-meta">
            <span>官方维护的 Homebrew tap</span>
            <a
              href="https://github.com/taobaorun/homebrew-keep3"
              target="_blank"
              rel="noreferrer"
            >
              查看仓库 ↗
            </a>
          </div>
        </article>
      </div>

      {showUnsignedGuide && <UnsignedFirstLaunchGuide />}

      <div className="download-details">
        <div className="system-requirements">
          <p className="detail-label">SYSTEM REQUIREMENTS</p>
          <ul>
            <li>macOS 14 或更高版本</li>
            <li>Apple silicon（arm64）Mac</li>
            <li>约 5 MB 下载空间</li>
          </ul>
        </div>

        <div className="first-launch">
          <p className="detail-label">FIRST LAUNCH</p>
          {release?.trustState === "developer-id" ? (
            <p>该版本已经 Developer ID 签名并通过 Apple 公证，可按标准流程打开。</p>
          ) : release ? (
            <p>
              当前版本未使用 Developer ID 签名，也未经过 Apple 公证。首次打开时，
              macOS 可能要求你在“系统设置 → 隐私与安全性”中确认打开。
            </p>
          ) : (
            <p>
              下载前会验证正式发布元数据。若自动校验不可用，请在 GitHub Releases
              查看当前版本和首次打开说明。
            </p>
          )}
        </div>

      </div>
    </section>
  );
}
