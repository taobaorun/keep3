#!/bin/sh
set -eu

fail() {
  printf 'refresh-release-status: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: refresh-release-status.sh --current JSON --status JSON
  --public-key PEM --expected-key-id ID --private-key PEM
  --published-at ISO8601 --expires-at ISO8601 --output JSON

Refreshes only a signed Converged operational status. The stable current
document and immutable release manifest are never rewritten.
USAGE
  exit 64
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
current=''; status=''; public_key=''; expected_key_id=''; private_key=''
published_at=''; expires_at=''; output=''

while test "$#" -gt 0; do
  case "$1" in
    --current) current=${2-}; shift 2 ;;
    --status) status=${2-}; shift 2 ;;
    --public-key) public_key=${2-}; shift 2 ;;
    --expected-key-id) expected_key_id=${2-}; shift 2 ;;
    --private-key) private_key=${2-}; shift 2 ;;
    --published-at) published_at=${2-}; shift 2 ;;
    --expires-at) expires_at=${2-}; shift 2 ;;
    --output) output=${2-}; shift 2 ;;
    --help|-h) usage ;;
    *) usage ;;
  esac
done

for required_file in "$current" "$status" "$public_key" "$private_key"; do
  test -f "$required_file" || fail "required input is missing: $required_file"
done
test -n "$expected_key_id" && test -n "$published_at" \
  && test -n "$expires_at" && test -n "$output" \
  || fail "key ID, timestamps, and output are required"

signer="$script_dir/sign-release-metadata.sh"
for document in "$current" "$status"; do
  "$signer" verify --input "$document" --public-key "$public_key" \
    --expected-key-id "$expected_key_id" >/dev/null \
    || fail "signed discovery input is invalid: $(basename -- "$document")"
done

mkdir -p "$(dirname -- "$output")"
unsigned="$output.unsigned.$$"
trap 'rm -f "$unsigned"' EXIT HUP INT TERM

/usr/bin/ruby -rjson -rtime -e '
  current_path, status_path, published_value, expires_value, key_id, output = ARGV
  current = JSON.parse(File.read(current_path))
  status = JSON.parse(File.read(status_path))
  abort "unknown current schema" unless current["schemaVersion"] == 1
  abort "unknown status schema" unless status["schemaVersion"] == 1
  stable = current.fetch("signed")
  operational = status.fetch("signed")
  [stable, operational].each do |signed|
    abort "unexpected repository" unless signed["repository"] == "taobaorun/keep3"
    abort "unexpected canonical origin" unless signed["canonicalOrigin"] == "https://taobaorun.github.io"
    abort "metadata key mismatch" unless signed["keyId"] == key_id
  end
  abort "current is not converged" unless stable["state"] == "Converged"
  abort "current discovery must not expire" if stable.key?("expiresAt")
  version = stable.fetch("version")
  tag = stable.fetch("tag")
  build = stable.fetch("build")
  release_sequence = stable.fetch("sequence")
  abort "invalid stable version" unless
    version.match?(/\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z/)
  abort "stable tag/version mismatch" unless tag == "v#{version}"
  abort "invalid stable build" unless build.is_a?(Integer) && build.positive?
  abort "invalid stable sequence" unless
    release_sequence.is_a?(Integer) && release_sequence.positive?
  abort "unknown stable trust state" unless
    %w[unsigned developer-id].include?(stable["trustState"])
  abort "unexpected stable fallback" unless
    stable["fallbackUrl"] == "https://github.com/taobaorun/keep3/releases"
  abort "only a converged status can be refreshed" unless operational["state"] == "Converged"
  manifest_url = "https://taobaorun.github.io/keep3/release-channel/releases/#{tag}/manifest.json"
  artifact_url = "https://github.com/taobaorun/keep3/releases/download/#{tag}/Keep3-#{version}.dmg"
  abort "unexpected stable manifest" unless stable["manifestUrl"] == manifest_url
  abort "unexpected stable artifact" unless stable["artifactUrl"] == artifact_url
  abort "unexpected operational fallback" unless
    operational["fallbackUrl"] == "https://github.com/taobaorun/keep3/releases"
  abort "status does not identify current" unless
    operational["currentManifestUrl"] == manifest_url &&
      operational["candidateManifestUrl"] == manifest_url
  %w[version build tag trustState].each do |field|
    abort "status release identity mismatch" unless operational[field] == stable[field]
  end
  old_sequence = operational.fetch("sequence")
  abort "invalid status sequence" unless old_sequence.is_a?(Integer) && old_sequence.positive?
  old_published = Time.iso8601(operational.fetch("publishedAt"))
  old_expires = Time.iso8601(operational.fetch("expiresAt"))
  stable_published = Time.iso8601(stable.fetch("publishedAt"))
  abort "invalid prior status lifetime" unless old_published < old_expires
  published = Time.iso8601(published_value)
  expires = Time.iso8601(expires_value)
  abort "refresh predates stable discovery" unless stable_published <= published
  abort "refresh does not advance publication time" unless old_published < published
  abort "status refresh must last exactly 90 days" unless
    expires - published == 90 * 24 * 60 * 60
  refreshed = Marshal.load(Marshal.dump(status))
  signed = refreshed.fetch("signed")
  signed["sequence"] = old_sequence + 1
  signed["publishedAt"] = published.utc.iso8601
  signed["expiresAt"] = expires.utc.iso8601
  signed["message"] = "Stable release discovery freshness was renewed."
  File.write(output, JSON.pretty_generate(refreshed.reject { |key, _| key == "signature" }) + "\n")
' "$current" "$status" "$published_at" "$expires_at" \
  "$expected_key_id" "$unsigned" \
  || fail "release status cannot be refreshed"

"$signer" sign --input "$unsigned" --output "$output" \
  --private-key "$private_key" --key-id "$expected_key_id" \
  || fail "refreshed release status could not be signed"

printf '%s\n' "$output"
