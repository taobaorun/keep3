#!/bin/sh
set -eu

fail() {
  printf 'generate-channel-metadata: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: generate-channel-metadata.sh --dmg FILE --version X.Y.Z --build N
  --tag vX.Y.Z --sequence N --commit SHA --sparkle-signature BASE64
  --published-at ISO8601 --expires-at ISO8601 --key-id ID --output-dir DIR
  [--trust-state unsigned|developer-id] [--xcode-version VALUE]
  [--sdk-version VALUE] [--macos-version VALUE]
USAGE
  exit 64
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
dmg=''; version=''; build=''; tag=''; sequence=''; commit=''
sparkle_signature=''; published_at=''; expires_at=''; key_id=''; output_dir=''
trust_state='unsigned'; xcode_version='unknown'; sdk_version='unknown'; macos_version='unknown'

while test "$#" -gt 0; do
  case "$1" in
    --dmg) dmg=${2-}; shift 2 ;;
    --version) version=${2-}; shift 2 ;;
    --build) build=${2-}; shift 2 ;;
    --tag) tag=${2-}; shift 2 ;;
    --sequence) sequence=${2-}; shift 2 ;;
    --commit) commit=${2-}; shift 2 ;;
    --sparkle-signature) sparkle_signature=${2-}; shift 2 ;;
    --published-at) published_at=${2-}; shift 2 ;;
    --expires-at) expires_at=${2-}; shift 2 ;;
    --key-id) key_id=${2-}; shift 2 ;;
    --output-dir) output_dir=${2-}; shift 2 ;;
    --trust-state) trust_state=${2-}; shift 2 ;;
    --xcode-version) xcode_version=${2-}; shift 2 ;;
    --sdk-version) sdk_version=${2-}; shift 2 ;;
    --macos-version) macos_version=${2-}; shift 2 ;;
    --help|-h) usage ;;
    *) usage ;;
  esac
done

test -f "$dmg" || fail "--dmg must name an existing file"
printf '%s\n' "$version" | /usr/bin/ruby -e '
  value = STDIN.read.strip
  exit(value.match?(/\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z/) ? 0 : 1)
' || fail "invalid version"
test "$tag" = "v$version" || fail "tag must equal v<version>"
case "$build" in ''|*[!0-9]*) fail "build must be numeric" ;; esac
case "$sequence" in ''|*[!0-9]*) fail "sequence must be numeric" ;; esac
test "$build" -gt 0 || fail "build must be positive"
test "$sequence" -gt 0 || fail "sequence must be positive"
case "$commit" in *[!0-9a-f]*|'') fail "commit must be lowercase hexadecimal" ;; esac
test "${#commit}" -eq 40 || fail "commit must contain 40 hexadecimal characters"
case "$trust_state" in unsigned|developer-id) ;; *) fail "unknown trust state" ;; esac
test -n "$sparkle_signature" || fail "Sparkle EdDSA signature is required"
test -n "$published_at" && test -n "$expires_at" || fail "timestamps are required"
test -n "$key_id" || fail "metadata key identifier is required"
printf '%s\n' "$key_id" | /usr/bin/ruby -e '
  value = STDIN.read.strip
  exit(value.match?(/\Akeep3-release-metadata-[a-z0-9-]+\z/) ? 0 : 1)
' || fail "invalid metadata key identifier"
test -n "$output_dir" || fail "output directory is required"
mkdir -p "$output_dir"

sha256=$(shasum -a 256 "$dmg" | awk '{print $1}')
size=$(stat -f '%z' "$dmg")
file_name="Keep3-$version.dmg"
test "$(basename -- "$dmg")" = "$file_name" || fail "DMG filename does not match version"

manifest="$output_dir/manifest.unsigned.json"
current="$output_dir/current-release.unsigned.json"
status="$output_dir/release-status.unsigned.json"
appcast="$output_dir/appcast.xml"
cask="$output_dir/keep3.rb"

/usr/bin/ruby -rjson -rtime -e '
  version, build, tag, sequence, commit, signature, published_at,
    expires_at, key_id, trust_state, file_name, sha256, size,
    xcode_version, sdk_version, macos_version, manifest_path,
    current_path, status_path = ARGV
  build = Integer(build); sequence = Integer(sequence); size = Integer(size)
  published_time = Time.iso8601(published_at)
  expires_time = Time.iso8601(expires_at)
  abort "operational status lifetime must be exactly 90 days" unless
    expires_time - published_time == 90 * 24 * 60 * 60
  artifact_url = "https://github.com/taobaorun/keep3/releases/download/#{tag}/#{file_name}"
  manifest_url = "https://taobaorun.github.io/keep3/release-channel/releases/#{tag}/manifest.json"
  common = {
    "repository" => "taobaorun/keep3", "canonicalOrigin" => "https://taobaorun.github.io",
    "sequence" => sequence, "version" => version, "build" => build,
    "tag" => tag, "trustState" => trust_state, "publishedAt" => published_at,
    "keyId" => key_id
  }
  manifest = {
    "schemaVersion" => 1,
    "signed" => common.merge(
      "artifact" => {
        "fileName" => file_name, "url" => artifact_url, "sha256" => sha256,
        "size" => size, "sparkleEdSignature" => signature
      },
      "source" => {
        "tagUrl" => "https://github.com/taobaorun/keep3/tree/#{tag}",
        "archiveUrl" => "https://github.com/taobaorun/keep3/archive/refs/tags/#{tag}.tar.gz",
        "commit" => commit
      },
      "channels" => {
        "manifestUrl" => manifest_url,
        "appcastUrl" => "https://taobaorun.github.io/keep3/release-channel/appcast.xml",
        "homebrewTap" => "taobaorun/keep3", "homebrewCaskPath" => "Casks/keep3.rb"
      },
      "provenance" => {
        "builtAt" => published_at, "gitCommit" => commit,
        "xcodeVersion" => xcode_version, "sdkVersion" => sdk_version,
        "macOSVersion" => macos_version, "candidateDigest" => sha256
      }
    )
  }
  current = {
    "schemaVersion" => 1,
    "signed" => common.merge(
      "state" => "Converged", "manifestUrl" => manifest_url,
      "artifactUrl" => artifact_url,
      "fallbackUrl" => "https://github.com/taobaorun/keep3/releases"
    )
  }
  status = {
    "schemaVersion" => 1,
    "signed" => common.merge(
      "expiresAt" => expires_at,
      "state" => "Candidate", "candidateManifestUrl" => manifest_url,
      "currentManifestUrl" => nil,
      "message" => "Candidate is private and has not moved current release discovery.",
      "fallbackUrl" => "https://github.com/taobaorun/keep3/releases"
    )
  }
  [[manifest_path, manifest], [current_path, current], [status_path, status]].each do |path, document|
    File.write(path, JSON.pretty_generate(document) + "\n")
  end
' "$version" "$build" "$tag" "$sequence" "$commit" "$sparkle_signature" \
  "$published_at" "$expires_at" "$key_id" "$trust_state" "$file_name" \
  "$sha256" "$size" "$xcode_version" "$sdk_version" "$macos_version" \
  "$manifest" "$current" "$status" \
  || fail "could not generate JSON channel metadata"

/usr/bin/ruby -rjson -rcgi -e '
  signed = JSON.parse(File.read(ARGV.fetch(0))).fetch("signed")
  artifact = signed.fetch("artifact")
  xml = <<~XML
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <title>Keep3 Updates</title>
        <link>https://taobaorun.github.io/keep3/release-channel/appcast.xml</link>
        <item>
          <title>Keep3 #{CGI.escapeHTML(signed.fetch("version"))}</title>
          <pubDate>#{CGI.escapeHTML(signed.fetch("publishedAt"))}</pubDate>
          <enclosure url="#{CGI.escapeHTML(artifact.fetch("url"))}" length="#{artifact.fetch("size")}" type="application/octet-stream" sparkle:version="#{signed.fetch("build")}" sparkle:shortVersionString="#{CGI.escapeHTML(signed.fetch("version"))}" sparkle:edSignature="#{CGI.escapeHTML(artifact.fetch("sparkleEdSignature"))}" />
        </item>
      </channel>
    </rss>
  XML
  File.write(ARGV.fetch(1), xml)
' "$manifest" "$appcast" || fail "could not generate appcast"

"$script_dir/render-homebrew-cask.sh" \
  --manifest "$manifest" \
  --template "$repository_root/distribution/homebrew/Casks/keep3.rb.template" \
  --output "$cask"

printf '%s\n' "$manifest"
