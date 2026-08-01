#!/bin/sh
set -eu

fail() {
  printf 'validate-release: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: validate-release.sh --manifest JSON --dmg FILE --app Keep3.app
  --public-key PEM --expected-key-id ID --tag vX.Y.Z --now ISO8601
  --appcast XML --cask RB --sparkle-sign-update FILE
  --sparkle-private-key FILE [--current JSON] [--status JSON]
  [--minimum-sequence N] [--expected-commit SHA]
USAGE
  exit 64
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
manifest=''; dmg=''; app=''; public_key=''; expected_key_id=''; tag=''
now=''; appcast=''; cask=''; current=''; status=''; minimum_sequence='0'
expected_commit=''
sparkle_sign_update=''; sparkle_private_key=''
while test "$#" -gt 0; do
  case "$1" in
    --manifest) manifest=${2-}; shift 2 ;;
    --dmg) dmg=${2-}; shift 2 ;;
    --app) app=${2-}; shift 2 ;;
    --public-key) public_key=${2-}; shift 2 ;;
    --expected-key-id) expected_key_id=${2-}; shift 2 ;;
    --tag) tag=${2-}; shift 2 ;;
    --now) now=${2-}; shift 2 ;;
    --appcast) appcast=${2-}; shift 2 ;;
    --cask) cask=${2-}; shift 2 ;;
    --current) current=${2-}; shift 2 ;;
    --status) status=${2-}; shift 2 ;;
    --minimum-sequence) minimum_sequence=${2-}; shift 2 ;;
    --expected-commit) expected_commit=${2-}; shift 2 ;;
    --sparkle-sign-update) sparkle_sign_update=${2-}; shift 2 ;;
    --sparkle-private-key) sparkle_private_key=${2-}; shift 2 ;;
    --help|-h) usage ;;
    *) usage ;;
  esac
done

for required_file in "$manifest" "$dmg" "$app/Contents/Info.plist" \
  "$public_key" "$appcast" "$cask" "$sparkle_sign_update" \
  "$sparkle_private_key"; do
  test -f "$required_file" || fail "required input is missing: $required_file"
done
test -n "$expected_key_id" && test -n "$tag" && test -n "$now" \
  || fail "key ID, tag, and validation time are required"
case "$minimum_sequence" in ''|*[!0-9]*) fail "minimum sequence must be numeric" ;; esac

"$script_dir/sign-release-metadata.sh" verify \
  --input "$manifest" --public-key "$public_key" \
  --expected-key-id "$expected_key_id" \
  || fail "manifest metadata signature is invalid"
if test -n "$current"; then
  test -f "$current" || fail "current document does not exist"
  "$script_dir/sign-release-metadata.sh" verify \
    --input "$current" --public-key "$public_key" \
    --expected-key-id "$expected_key_id" \
    || fail "current metadata signature is invalid"
fi
if test -n "$status"; then
  test -f "$status" || fail "status document does not exist"
  "$script_dir/sign-release-metadata.sh" verify \
    --input "$status" --public-key "$public_key" \
    --expected-key-id "$expected_key_id" \
    || fail "status metadata signature is invalid"
fi

actual_sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
actual_size=$(stat -f '%z' "$dmg")
app_bundle_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw \
  "$app/Contents/Info.plist") || fail "built app has no bundle identifier"
app_version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw \
  "$app/Contents/Info.plist") || fail "built app has no marketing version"
app_build=$(/usr/bin/plutil -extract CFBundleVersion raw \
  "$app/Contents/Info.plist") || fail "built app has no build version"
test "$app_bundle_id" = "dev.keep3.Keep3" \
  || fail "built app uses an unexpected bundle identifier"

/usr/bin/ruby -rjson -rtime -e '
  def fail!(message)
    warn message
    exit 1
  end
  manifest_path, tag, expected_key_id, now_value, actual_sha,
    actual_size, dmg_name, minimum_sequence, expected_commit,
    current_path, status_path, appcast_path, cask_path,
    app_version, app_build = ARGV
  document = JSON.parse(File.read(manifest_path))
  fail!("unknown manifest schema") unless document["schemaVersion"] == 1
  signed = document.fetch("signed")
  signature = document.fetch("signature")
  fail!("unexpected repository") unless signed["repository"] == "taobaorun/keep3"
  fail!("unexpected canonical origin") unless signed["canonicalOrigin"] == "https://taobaorun.github.io"
  fail!("metadata key mismatch") unless signed["keyId"] == expected_key_id && signature["keyId"] == expected_key_id
  version = signed.fetch("version")
  fail!("invalid semantic version") unless version.match?(/\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z/)
  fail!("tag/version mismatch") unless tag == "v#{version}" && signed["tag"] == tag
  build = signed.fetch("build")
  sequence = signed.fetch("sequence")
  fail!("build must be positive numeric") unless build.is_a?(Integer) && build.positive?
  fail!("sequence must be positive numeric") unless sequence.is_a?(Integer) && sequence.positive?
  fail!("app marketing version mismatch") unless app_version == version
  fail!("app build version mismatch") unless app_build == build.to_s
  fail!("replayed metadata sequence") unless sequence > Integer(minimum_sequence)
  fail!("unknown trust state") unless %w[unsigned developer-id].include?(signed["trustState"])
  now = Time.iso8601(now_value)
  published = Time.iso8601(signed.fetch("publishedAt"))
  expires = Time.iso8601(signed.fetch("expiresAt"))
  fail!("invalid metadata lifetime") unless published < expires
  fail!("metadata publication is in the future") unless published <= now
  fail!("metadata expired") unless now < expires
  artifact = signed.fetch("artifact")
  expected_name = "Keep3-#{version}.dmg"
  expected_url = "https://github.com/taobaorun/keep3/releases/download/#{tag}/#{expected_name}"
  fail!("artifact filename mismatch") unless artifact["fileName"] == expected_name && dmg_name == expected_name
  fail!("mutable or unexpected artifact URL") unless artifact["url"] == expected_url
  fail!("artifact checksum mismatch") unless artifact["sha256"] == actual_sha
  fail!("artifact size mismatch") unless artifact["size"] == Integer(actual_size)
  sparkle_signature = artifact["sparkleEdSignature"]
  fail!("missing Sparkle signature") unless sparkle_signature.is_a?(String) && sparkle_signature.match?(/\A[A-Za-z0-9+\/]{86}==\z/)
  source = signed.fetch("source")
  fail!("wrong source tag URL") unless source["tagUrl"] == "https://github.com/taobaorun/keep3/tree/#{tag}"
  fail!("wrong source archive URL") unless source["archiveUrl"] == "https://github.com/taobaorun/keep3/archive/refs/tags/#{tag}.tar.gz"
  fail!("invalid source commit") unless source["commit"].match?(/\A[0-9a-f]{40}\z/)
  fail!("source commit mismatch") unless expected_commit.empty? || source["commit"] == expected_commit
  channels = signed.fetch("channels")
  expected_manifest_url = "https://taobaorun.github.io/keep3/release-channel/releases/#{tag}/manifest.json"
  fail!("unexpected manifest URL") unless channels["manifestUrl"] == expected_manifest_url
  fail!("unexpected appcast URL") unless channels["appcastUrl"] == "https://taobaorun.github.io/keep3/release-channel/appcast.xml"
  fail!("unexpected Homebrew projection") unless channels["homebrewTap"] == "taobaorun/keep3" && channels["homebrewCaskPath"] == "Casks/keep3.rb"
  provenance = signed.fetch("provenance")
  fail!("candidate digest mismatch") unless provenance["candidateDigest"] == actual_sha
  fail!("provenance commit mismatch") unless provenance["gitCommit"] == source["commit"]
  appcast = File.read(appcast_path)
  [expected_url, "sparkle:version=\"#{build}\"", "sparkle:shortVersionString=\"#{version}\"", "sparkle:edSignature=\"#{sparkle_signature}\""].each do |needle|
    fail!("appcast projection mismatch") unless appcast.include?(needle)
  end
  cask = File.read(cask_path)
  ["version \"#{version}\"", "sha256 \"#{actual_sha}\"", "url \"#{expected_url}\""].each do |needle|
    fail!("Homebrew projection mismatch") unless cask.include?(needle)
  end
  fail!("cask weakens quarantine") if cask.match?(/xattr|no_check|version\s+:latest/)
  unless current_path.empty?
    current_document = JSON.parse(File.read(current_path))
    fail!("unknown current schema") unless current_document["schemaVersion"] == 1
    current = current_document.fetch("signed")
    fail!("unexpected current repository") unless current["repository"] == "taobaorun/keep3"
    fail!("unexpected current origin") unless current["canonicalOrigin"] == "https://taobaorun.github.io"
    fail!("current key mismatch") unless current["keyId"] == expected_key_id
    fail!("current state is not converged") unless current["state"] == "Converged"
    current_version = current.fetch("version")
    current_tag = current.fetch("tag")
    fail!("invalid current version") unless current_version.match?(/\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z/)
    fail!("current tag/version mismatch") unless current_tag == "v#{current_version}"
    fail!("unknown current trust state") unless %w[unsigned developer-id].include?(current["trustState"])
    current_published = Time.iso8601(current.fetch("publishedAt"))
    current_expires = Time.iso8601(current.fetch("expiresAt"))
    fail!("invalid current lifetime") unless current_published < current_expires && current_published <= now
    fail!("current document is expired") unless now < current_expires
    current_manifest_url = "https://taobaorun.github.io/keep3/release-channel/releases/#{current_tag}/manifest.json"
    current_artifact_url = "https://github.com/taobaorun/keep3/releases/download/#{current_tag}/Keep3-#{current_version}.dmg"
    fail!("unexpected current manifest URL") unless current["manifestUrl"] == current_manifest_url
    fail!("unexpected current artifact URL") unless current["artifactUrl"] == current_artifact_url
    fail!("invalid current build") unless current["build"].is_a?(Integer) && current["build"].positive?
    fail!("invalid current sequence") unless current["sequence"].is_a?(Integer) && current["sequence"].positive?
    fail!("candidate build is not monotonic") unless build > current.fetch("build")
    fail!("candidate sequence is not monotonic") unless sequence > current.fetch("sequence")
  end
  unless status_path.empty?
    status_document = JSON.parse(File.read(status_path))
    fail!("unknown status schema") unless status_document["schemaVersion"] == 1
    status = status_document.fetch("signed")
    fail!("unexpected status repository") unless status["repository"] == "taobaorun/keep3"
    fail!("unexpected status origin") unless status["canonicalOrigin"] == "https://taobaorun.github.io"
    fail!("status key mismatch") unless status["keyId"] == expected_key_id
    allowed = %w[NoRelease Candidate Promoting Degraded Converged Compromised]
    fail!("unknown operational state") unless allowed.include?(status["state"])
    status_published = Time.iso8601(status.fetch("publishedAt"))
    status_expires = Time.iso8601(status.fetch("expiresAt"))
    fail!("invalid status lifetime") unless status_published < status_expires && status_published <= now
    fail!("status document is expired") unless now < status_expires
    fail!("invalid status sequence") unless status["sequence"].is_a?(Integer) && status["sequence"].positive?
    [status["candidateManifestUrl"], status["currentManifestUrl"]].compact.each do |url|
      fail!("unexpected status manifest URL") unless url.match?(%r{\Ahttps://taobaorun\.github\.io/keep3/release-channel/releases/v[0-9]+\.[0-9]+\.[0-9]+/manifest\.json\z})
    end
    if status["state"] == "NoRelease"
      %w[version build tag trustState candidateManifestUrl currentManifestUrl].each do |field|
        fail!("NoRelease status contains release data") unless status[field].nil?
      end
    elsif %w[Candidate Promoting Degraded].include?(status["state"])
      fail!("active candidate status is missing manifest") unless status["candidateManifestUrl"] == expected_manifest_url
      fail!("candidate status version mismatch") unless status["version"] == version && status["build"] == build && status["tag"] == tag
    elsif status["state"] == "Converged"
      fail!("converged status does not identify current") unless status["currentManifestUrl"] == expected_manifest_url
    end
    fail!("release channels are frozen") if status["state"] == "Compromised"
  end
' "$manifest" "$tag" "$expected_key_id" "$now" "$actual_sha" \
  "$actual_size" "$(basename -- "$dmg")" "$minimum_sequence" \
  "$expected_commit" "$current" "$status" "$appcast" "$cask" \
  "$app_version" "$app_build" \
  || fail "release contract validation failed"

feed_url=$(/usr/bin/plutil -extract SUFeedURL raw "$app/Contents/Info.plist") \
  || fail "built app has no Sparkle feed URL"
test "$feed_url" = "https://taobaorun.github.io/keep3/release-channel/appcast.xml" \
  || fail "built app uses an unexpected Sparkle feed"
sparkle_key=$(/usr/bin/plutil -extract SUPublicEDKey raw "$app/Contents/Info.plist") \
  || fail "built app has no Sparkle public key"
test -n "$sparkle_key" || fail "built app has an empty Sparkle public key"
fixture_sparkle_key='eRFPLZuNM6m8bltmtpPX4fzKbufI1z6rKJHtgIIsllk='
test "$sparkle_key" != "$fixture_sparkle_key" \
  || fail "production validation rejects Sparkle's fixture public key"

sparkle_signature=$(/usr/bin/ruby -rjson -e '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  puts document.fetch("signed").fetch("artifact").fetch("sparkleEdSignature")
' "$manifest") || fail "could not read Sparkle signature"
"$sparkle_sign_update" \
  --ed-key-file "$sparkle_private_key" \
  --verify "$dmg" "$sparkle_signature" \
  || fail "Sparkle archive signature is invalid"
"$sparkle_sign_update" \
  --ed-key-file "$sparkle_private_key" \
  --verify "$appcast" \
  || fail "Sparkle appcast signature is invalid"

derived_sparkle_public_key=$(xcrun swift - "$sparkle_private_key" <<'SWIFT'
import CryptoKit
import Foundation

let path = CommandLine.arguments[1]
let encoded = try String(contentsOfFile: path, encoding: .utf8)
  .trimmingCharacters(in: .whitespacesAndNewlines)
guard let decoded = Data(base64Encoded: encoded) else {
  fatalError("Sparkle private key is not base64")
}
let publicKey: Data
if decoded.count == 32 {
  publicKey = try Curve25519.Signing.PrivateKey(
    rawRepresentation: decoded
  ).publicKey.rawRepresentation
} else if decoded.count == 96 {
  publicKey = decoded.suffix(32)
} else {
  fatalError("unsupported Sparkle private key format")
}
print(publicKey.base64EncodedString())
SWIFT
) || fail "could not derive Sparkle public key"
test "$sparkle_key" = "$derived_sparkle_public_key" \
  || fail "built app does not embed the candidate signing key"

printf 'validate-release: passed\n'
