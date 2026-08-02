const REPOSITORY = "taobaorun/keep3";
const CANONICAL_ORIGIN = "https://taobaorun.github.io";
const RELEASE_CHANNEL = `${CANONICAL_ORIGIN}/keep3/release-channel`;
const CURRENT_RELEASE_URL = `${RELEASE_CHANNEL}/current-release.json`;
const RELEASE_STATUS_URL = `${RELEASE_CHANNEL}/release-status.json`;
const FALLBACK_URL = "https://github.com/taobaorun/keep3/releases";
const KEY_ID = "keep3-release-metadata-production";
const MAX_METADATA_BYTES = 64 * 1024;
const VERSION_PATTERN = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;

const PUBLIC_KEY_PEM = `-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAEKSoAMb3vJvXLvoltGcEJ2c0e/GN2oPhYbgRrz7R1t0=
-----END PUBLIC KEY-----`;

export class ReleaseChannelError extends Error {
  constructor(message) {
    super(message);
    this.name = "ReleaseChannelError";
  }
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requireRecord(value, name) {
  if (!isRecord(value)) {
    throw new ReleaseChannelError(`${name} must be an object`);
  }
  return value;
}

function requireString(value, name) {
  if (typeof value !== "string" || value.length === 0) {
    throw new ReleaseChannelError(`${name} must be a non-empty string`);
  }
  return value;
}

function canonicalize(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalize).join(",")}]`;
  }

  if (isRecord(value)) {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalize(value[key])}`)
      .join(",")}}`;
  }

  const encoded = JSON.stringify(value);
  if (encoded === undefined) {
    throw new ReleaseChannelError("metadata contains an unsupported value");
  }
  return encoded;
}

function base64ToBytes(value) {
  try {
    return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
  } catch {
    throw new ReleaseChannelError("metadata contains invalid base64");
  }
}

function publicKeyBytes() {
  return base64ToBytes(
    PUBLIC_KEY_PEM.replace(/-----[^-]+-----|\s/g, ""),
  );
}

function assertIdentity(signed, name) {
  if (signed.repository !== REPOSITORY) {
    throw new ReleaseChannelError(`${name} repository is not trusted`);
  }
  if (signed.canonicalOrigin !== CANONICAL_ORIGIN) {
    throw new ReleaseChannelError(`${name} origin is not trusted`);
  }
  if (signed.keyId !== KEY_ID) {
    throw new ReleaseChannelError(`${name} key is not trusted`);
  }
}

function assertVersion(value, name) {
  const version = requireString(value, name);
  if (!VERSION_PATTERN.test(version)) {
    throw new ReleaseChannelError(`${name} is invalid`);
  }
  return version;
}

function assertPositiveInteger(value, name) {
  if (!Number.isInteger(value) || value < 1) {
    throw new ReleaseChannelError(`${name} must be a positive integer`);
  }
  return value;
}

function assertTrustState(value, name) {
  if (value !== "unsigned" && value !== "developer-id") {
    throw new ReleaseChannelError(`${name} is unsupported`);
  }
  return value;
}

function assertMatching(value, expected, name) {
  if (value !== expected) {
    throw new ReleaseChannelError(`${name} does not match the verified release`);
  }
}

function assertManifestUrl(value, tag) {
  const expected = `${RELEASE_CHANNEL}/releases/${tag}/manifest.json`;
  assertMatching(value, expected, "manifest URL");
  return expected;
}

/** Verify one release metadata envelope with the pinned production key. */
export async function verifyEnvelope(envelope) {
  const root = requireRecord(envelope, "metadata envelope");
  if (root.schemaVersion !== 1) {
    throw new ReleaseChannelError("metadata schema version is unsupported");
  }

  const signed = requireRecord(root.signed, "metadata signed payload");
  const signature = requireRecord(root.signature, "metadata signature");
  if (signature.algorithm !== "Ed25519") {
    throw new ReleaseChannelError("metadata signature algorithm is unsupported");
  }
  if (signature.keyId !== KEY_ID || signed.keyId !== KEY_ID) {
    throw new ReleaseChannelError("metadata signature key is not trusted");
  }

  const subtle = globalThis.crypto?.subtle;
  if (!subtle) {
    throw new ReleaseChannelError("this browser cannot verify release metadata");
  }

  let publicKey;
  try {
    publicKey = await subtle.importKey(
      "spki",
      publicKeyBytes(),
      { name: "Ed25519" },
      false,
      ["verify"],
    );
  } catch {
    throw new ReleaseChannelError("this browser cannot import the release key");
  }

  const unsignedEnvelope = Object.fromEntries(
    Object.entries(root).filter(([key]) => key !== "signature"),
  );
  const payload = new TextEncoder().encode(canonicalize(unsignedEnvelope));
  const signatureBytes = base64ToBytes(
    requireString(signature.value, "metadata signature"),
  );

  let verified = false;
  try {
    verified = await subtle.verify(
      { name: "Ed25519" },
      publicKey,
      signatureBytes,
      payload,
    );
  } catch {
    throw new ReleaseChannelError("release metadata verification failed");
  }

  if (!verified) {
    throw new ReleaseChannelError("release metadata signature is invalid");
  }
  return signed;
}

/** Convert three already verified payloads into the single download contract. */
export function resolveVerifiedRelease({ status, current, manifest, now = new Date() }) {
  const statusPayload = requireRecord(status, "release status");
  const currentPayload = requireRecord(current, "current release");
  const manifestPayload = requireRecord(manifest, "release manifest");
  assertIdentity(statusPayload, "release status");
  assertIdentity(currentPayload, "current release");
  assertIdentity(manifestPayload, "release manifest");

  if (statusPayload.state !== "Converged" || currentPayload.state !== "Converged") {
    throw new ReleaseChannelError("release channel is not converged");
  }
  assertMatching(statusPayload.fallbackUrl, FALLBACK_URL, "fallback URL");
  assertMatching(currentPayload.fallbackUrl, FALLBACK_URL, "fallback URL");

  const expiry = new Date(requireString(statusPayload.expiresAt, "status expiry"));
  if (!Number.isFinite(expiry.getTime()) || now >= expiry) {
    throw new ReleaseChannelError("release status has expired");
  }

  const version = assertVersion(currentPayload.version, "release version");
  const build = assertPositiveInteger(currentPayload.build, "release build");
  const tag = `v${version}`;
  assertMatching(currentPayload.tag, tag, "release tag");
  const trustState = assertTrustState(
    currentPayload.trustState,
    "release trust state",
  );

  for (const [name, payload] of [
    ["release status", statusPayload],
    ["release manifest", manifestPayload],
  ]) {
    assertMatching(payload.version, version, `${name} version`);
    assertMatching(payload.build, build, `${name} build`);
    assertMatching(payload.tag, tag, `${name} tag`);
    assertMatching(payload.trustState, trustState, `${name} trust state`);
  }
  assertMatching(
    manifestPayload.sequence,
    currentPayload.sequence,
    "manifest sequence",
  );

  const manifestUrl = assertManifestUrl(currentPayload.manifestUrl, tag);
  assertMatching(
    statusPayload.currentManifestUrl,
    manifestUrl,
    "status manifest URL",
  );

  const artifact = requireRecord(manifestPayload.artifact, "release artifact");
  const expectedFileName = `Keep3-${version}.dmg`;
  const expectedArtifactUrl =
    `https://github.com/${REPOSITORY}/releases/download/${tag}/${expectedFileName}`;
  assertMatching(artifact.fileName, expectedFileName, "artifact file name");
  assertMatching(artifact.url, expectedArtifactUrl, "artifact URL");
  assertMatching(currentPayload.artifactUrl, expectedArtifactUrl, "current artifact URL");

  const sha256 = requireString(artifact.sha256, "artifact SHA-256");
  if (!/^[a-f0-9]{64}$/.test(sha256)) {
    throw new ReleaseChannelError("artifact SHA-256 is invalid");
  }
  const size = assertPositiveInteger(artifact.size, "artifact size");

  const source = requireRecord(manifestPayload.source, "release source");
  const tagUrl = `https://github.com/${REPOSITORY}/tree/${tag}`;
  assertMatching(source.tagUrl, tagUrl, "source tag URL");

  const channels = requireRecord(manifestPayload.channels, "release channels");
  assertMatching(channels.manifestUrl, manifestUrl, "channel manifest URL");
  assertMatching(channels.homebrewTap, "taobaorun/keep3", "Homebrew tap");
  assertMatching(channels.homebrewCaskPath, "Casks/keep3.rb", "Homebrew cask");

  return {
    version,
    build,
    trustState,
    artifactUrl: expectedArtifactUrl,
    fileName: expectedFileName,
    sha256,
    size,
    tagUrl,
  };
}

async function fetchJson(url, signal) {
  const response = await fetch(url, {
    headers: { accept: "application/json" },
    cache: "no-store",
    signal,
  });
  if (!response.ok) {
    throw new ReleaseChannelError(`release metadata request failed (${response.status})`);
  }

  const length = Number(response.headers.get("content-length"));
  if (Number.isFinite(length) && length > MAX_METADATA_BYTES) {
    throw new ReleaseChannelError("release metadata response is too large");
  }
  const body = await response.text();
  if (new TextEncoder().encode(body).byteLength > MAX_METADATA_BYTES) {
    throw new ReleaseChannelError("release metadata response is too large");
  }

  try {
    return JSON.parse(body);
  } catch {
    throw new ReleaseChannelError("release metadata is not valid JSON");
  }
}

/** Fetch and verify the full stable release chain. */
export async function fetchVerifiedRelease({ signal } = {}) {
  const statusEnvelope = await fetchJson(RELEASE_STATUS_URL, signal);
  const status = await verifyEnvelope(statusEnvelope);
  assertIdentity(status, "release status");
  if (status.state !== "Converged") {
    throw new ReleaseChannelError("release channel is not converged");
  }

  const currentEnvelope = await fetchJson(CURRENT_RELEASE_URL, signal);
  const current = await verifyEnvelope(currentEnvelope);
  assertIdentity(current, "current release");
  const version = assertVersion(current.version, "release version");
  const manifestUrl = assertManifestUrl(current.manifestUrl, `v${version}`);
  assertMatching(status.currentManifestUrl, manifestUrl, "status manifest URL");

  const manifestEnvelope = await fetchJson(manifestUrl, signal);
  const manifest = await verifyEnvelope(manifestEnvelope);

  return resolveVerifiedRelease({ status, current, manifest });
}

export const releaseChannel = {
  currentReleaseUrl: CURRENT_RELEASE_URL,
  releaseStatusUrl: RELEASE_STATUS_URL,
  fallbackUrl: FALLBACK_URL,
  homebrewCommand: "brew install --cask taobaorun/keep3/keep3",
};
