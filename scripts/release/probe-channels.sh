#!/bin/sh
set -eu

fail() {
  printf 'probe-channels: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: probe-channels.sh --mode fixture|live --tag vX.Y.Z --version X.Y.Z
  --build N --sha256 HEX --dmg-name FILE --manifest FILE --appcast FILE
  --cask FILE [--channel-root DIR] [--repository OWNER/REPO]
  [--canonical-origin URL] [--tap-cask-url URL] [--require-current]

Fixture mode performs only local filesystem reads. Live mode performs read-only
GitHub and HTTPS probes; it never publishes or mutates a channel.
USAGE
  exit 64
}

mode=''; tag=''; version=''; build=''; sha256=''; dmg_name=''
manifest=''; appcast=''; cask=''; channel_root=''; require_current=false
repository='taobaorun/keep3'
canonical_origin='https://taobaorun.github.io/keep3/release-channel'
tap_cask_url=''

while test "$#" -gt 0; do
  case "$1" in
    --mode) mode=${2-}; shift 2 ;;
    --tag) tag=${2-}; shift 2 ;;
    --version) version=${2-}; shift 2 ;;
    --build) build=${2-}; shift 2 ;;
    --sha256) sha256=${2-}; shift 2 ;;
    --dmg-name) dmg_name=${2-}; shift 2 ;;
    --manifest) manifest=${2-}; shift 2 ;;
    --appcast) appcast=${2-}; shift 2 ;;
    --cask) cask=${2-}; shift 2 ;;
    --channel-root) channel_root=${2-}; shift 2 ;;
    --repository) repository=${2-}; shift 2 ;;
    --canonical-origin) canonical_origin=${2-}; shift 2 ;;
    --tap-cask-url) tap_cask_url=${2-}; shift 2 ;;
    --require-current) require_current=true; shift ;;
    --help|-h) usage ;;
    *) usage ;;
  esac
done

case "$mode" in fixture|live) ;; *) usage ;; esac
test "$tag" = "v$version" || fail "tag and semantic version disagree"
case "$build" in ''|*[!0-9]*) fail "build must be numeric" ;; esac
test "$build" -gt 0 || fail "build must be positive"
case "$sha256" in *[!0-9a-f]*|'') fail "SHA-256 must be lowercase hexadecimal" ;; esac
test "${#sha256}" -eq 64 || fail "SHA-256 must contain 64 characters"
for file in "$manifest" "$appcast" "$cask"; do
  test -f "$file" || fail "probe input is missing: $file"
done

temporary_directory=$(mktemp -d /tmp/keep3-channel-probe-XXXXXX)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

if test "$mode" = fixture; then
  test -d "$channel_root" || fail "fixture channel root is missing"
  github_dir="$channel_root/github/releases/$tag"
  remote_dmg="$github_dir/$dmg_name"
  remote_manifest="$channel_root/pages/release-channel/releases/$tag/manifest.json"
  remote_appcast="$channel_root/pages/release-channel/appcast.xml"
  remote_cask="$channel_root/tap/Casks/keep3.rb"
  remote_current="$channel_root/pages/release-channel/current-release.json"
else
  command -v gh >/dev/null 2>&1 || fail "gh is required for live probes"
  command -v curl >/dev/null 2>&1 || fail "curl is required for live probes"
  github_dir="$temporary_directory/github"
  mkdir -p "$github_dir"
  gh release download "$tag" --repo "$repository" \
    --pattern "$dmg_name" --dir "$github_dir" >/dev/null
  remote_dmg="$github_dir/$dmg_name"
  remote_manifest="$temporary_directory/manifest.json"
  remote_appcast="$temporary_directory/appcast.xml"
  remote_cask="$temporary_directory/keep3.rb"
  remote_current="$temporary_directory/current-release.json"
  test -n "$tap_cask_url" || fail "--tap-cask-url is required for live probes"
  curl --connect-timeout 10 --max-time 60 \
    --fail --silent --show-error --location \
    "$canonical_origin/releases/$tag/manifest.json" -o "$remote_manifest"
  curl --connect-timeout 10 --max-time 60 \
    --fail --silent --show-error --location \
    "$canonical_origin/appcast.xml" -o "$remote_appcast"
  curl --connect-timeout 10 --max-time 60 \
    --fail --silent --show-error --location \
    "$tap_cask_url" -o "$remote_cask"
  if $require_current; then
    curl --connect-timeout 10 --max-time 60 \
      --fail --silent --show-error --location \
      "$canonical_origin/current-release.json" -o "$remote_current"
  fi
fi

test -f "$remote_dmg" || fail "GitHub release asset is missing"
actual_sha=$(shasum -a 256 "$remote_dmg" | awk '{print $1}')
test "$actual_sha" = "$sha256" || fail "GitHub release asset digest changed"
cmp -s "$manifest" "$remote_manifest" \
  || fail "immutable manifest does not match the candidate"
cmp -s "$appcast" "$remote_appcast" \
  || fail "active appcast does not match the candidate"
cmp -s "$cask" "$remote_cask" \
  || fail "tap cask does not match the candidate"

/usr/bin/ruby -rjson -e '
  manifest_path, appcast_path, cask_path, tag, version, build, sha = ARGV
  document = JSON.parse(File.read(manifest_path)).fetch("signed")
  artifact = document.fetch("artifact")
  abort "manifest version mismatch" unless document["tag"] == tag && document["version"] == version
  abort "manifest build mismatch" unless document["build"] == Integer(build)
  abort "manifest digest mismatch" unless artifact["sha256"] == sha
  expected_url = "https://github.com/taobaorun/keep3/releases/download/#{tag}/Keep3-#{version}.dmg"
  abort "manifest asset URL mismatch" unless artifact["url"] == expected_url
  appcast = File.read(appcast_path)
  abort "appcast version mismatch" unless appcast.include?("sparkle:version=\"#{build}\"")
  abort "appcast URL mismatch" unless appcast.include?(expected_url)
  cask = File.read(cask_path)
  abort "cask version mismatch" unless cask.include?("version \"#{version}\"")
  abort "cask checksum mismatch" unless cask.include?("sha256 \"#{sha}\"")
  expected_cask_url = %q{url "https://github.com/taobaorun/keep3/releases/download/v#{version}/Keep3-#{version}.dmg"}
  abort "cask URL mismatch" unless cask.include?(expected_cask_url)
  abort "cask weakens quarantine" if cask.match?(/xattr|sha256\s+:no_check|version\s+:latest/)
' "$remote_manifest" "$remote_appcast" "$remote_cask" \
  "$tag" "$version" "$build" "$sha256" \
  || fail "cross-channel version contract failed"

if $require_current; then
  test -f "$remote_current" || fail "current discovery document is missing"
  /usr/bin/ruby -rjson -e '
    current, tag, version, build = ARGV
    signed = JSON.parse(File.read(current)).fetch("signed")
    abort "current is not converged" unless signed["state"] == "Converged"
    abort "current release mismatch" unless signed["tag"] == tag && signed["version"] == version
    abort "current build mismatch" unless signed["build"] == Integer(build)
  ' "$remote_current" "$tag" "$version" "$build" \
    || fail "current discovery did not converge"
fi

printf 'probe-channels: passed\n'
