import assert from "node:assert/strict";
import test from "node:test";

import {
  ReleaseChannelError,
  resolveVerifiedRelease,
  verifyEnvelope,
} from "../app/lib/release-channel.mjs";

const currentEnvelope = {
  schemaVersion: 1,
  signed: {
    repository: "taobaorun/keep3",
    canonicalOrigin: "https://taobaorun.github.io",
    sequence: 1,
    version: "1.0.0",
    build: 1,
    tag: "v1.0.0",
    trustState: "unsigned",
    publishedAt: "2026-08-01T17:25:08Z",
    keyId: "keep3-release-metadata-production",
    state: "Converged",
    manifestUrl:
      "https://taobaorun.github.io/keep3/release-channel/releases/v1.0.0/manifest.json",
    artifactUrl:
      "https://github.com/taobaorun/keep3/releases/download/v1.0.0/Keep3-1.0.0.dmg",
    fallbackUrl: "https://github.com/taobaorun/keep3/releases",
  },
  signature: {
    algorithm: "Ed25519",
    keyId: "keep3-release-metadata-production",
    value:
      "0KEI6RVA56QIsTFPbsDriWP88MCJjG6YnsfBimh+EEFJNvTZK9T+yxKpr3nFf+B58nj0AVHOx63z9OHKHzqlBg==",
  },
};

const statusSigned = {
  repository: "taobaorun/keep3",
  canonicalOrigin: "https://taobaorun.github.io",
  sequence: 5,
  version: "1.0.0",
  build: 1,
  tag: "v1.0.0",
  trustState: "unsigned",
  publishedAt: "2026-08-01T17:25:08Z",
  keyId: "keep3-release-metadata-production",
  expiresAt: "2026-10-30T17:25:08Z",
  state: "Converged",
  currentManifestUrl:
    "https://taobaorun.github.io/keep3/release-channel/releases/v1.0.0/manifest.json",
  fallbackUrl: "https://github.com/taobaorun/keep3/releases",
};

const manifestSigned = {
  repository: "taobaorun/keep3",
  canonicalOrigin: "https://taobaorun.github.io",
  sequence: 1,
  version: "1.0.0",
  build: 1,
  tag: "v1.0.0",
  trustState: "unsigned",
  publishedAt: "2026-08-01T17:25:08Z",
  keyId: "keep3-release-metadata-production",
  artifact: {
    fileName: "Keep3-1.0.0.dmg",
    url: "https://github.com/taobaorun/keep3/releases/download/v1.0.0/Keep3-1.0.0.dmg",
    sha256: "f45e48261f9166c3f10102b38247fc7531090d5b5083f83f1bc0bdb4ddad9cef",
    size: 4_952_450,
  },
  source: {
    tagUrl: "https://github.com/taobaorun/keep3/tree/v1.0.0",
  },
  channels: {
    manifestUrl:
      "https://taobaorun.github.io/keep3/release-channel/releases/v1.0.0/manifest.json",
    homebrewTap: "taobaorun/keep3",
    homebrewCaskPath: "Casks/keep3.rb",
  },
};

test("accepts an envelope signed by the pinned production key", async () => {
  await assert.doesNotReject(() => verifyEnvelope(currentEnvelope));
});

test("rejects release metadata changed after signing", async () => {
  const tampered = structuredClone(currentEnvelope);
  tampered.signed.version = "9.9.9";

  await assert.rejects(() => verifyEnvelope(tampered), ReleaseChannelError);
});

test("resolves a consistent converged release into a direct download", () => {
  const release = resolveVerifiedRelease({
    status: statusSigned,
    current: currentEnvelope.signed,
    manifest: manifestSigned,
    now: new Date("2026-08-02T00:00:00Z"),
  });

  assert.deepEqual(release, {
    version: "1.0.0",
    build: 1,
    trustState: "unsigned",
    artifactUrl:
      "https://github.com/taobaorun/keep3/releases/download/v1.0.0/Keep3-1.0.0.dmg",
    fileName: "Keep3-1.0.0.dmg",
    sha256: "f45e48261f9166c3f10102b38247fc7531090d5b5083f83f1bc0bdb4ddad9cef",
    size: 4_952_450,
    tagUrl: "https://github.com/taobaorun/keep3/tree/v1.0.0",
  });
});

test("rejects an expired operational status", () => {
  assert.throws(
    () =>
      resolveVerifiedRelease({
        status: statusSigned,
        current: currentEnvelope.signed,
        manifest: manifestSigned,
        now: new Date("2026-11-01T00:00:00Z"),
      }),
    /expired/i,
  );
});

test("rejects a manifest that points at another artifact", () => {
  const inconsistentManifest = structuredClone(manifestSigned);
  inconsistentManifest.artifact.url =
    "https://github.com/taobaorun/keep3/releases/download/v1.0.0/Keep3-9.9.9.dmg";

  assert.throws(
    () =>
      resolveVerifiedRelease({
        status: statusSigned,
        current: currentEnvelope.signed,
        manifest: inconsistentManifest,
        now: new Date("2026-08-02T00:00:00Z"),
      }),
    /artifact/i,
  );
});
