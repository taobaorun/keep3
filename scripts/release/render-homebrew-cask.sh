#!/bin/sh
set -eu

fail() {
  printf 'render-homebrew-cask: %s\n' "$1" >&2
  exit 1
}

manifest=''
template=''
output=''
while test "$#" -gt 0; do
  case "$1" in
    --manifest) manifest=${2-}; shift 2 ;;
    --template) template=${2-}; shift 2 ;;
    --output) output=${2-}; shift 2 ;;
    *) fail "usage: --manifest JSON --template FILE --output FILE" ;;
  esac
done
test -f "$manifest" || fail "manifest does not exist"
test -f "$template" || fail "template does not exist"
test -n "$output" || fail "--output is required"
mkdir -p "$(dirname -- "$output")"

/usr/bin/ruby -rjson -e '
  manifest = JSON.parse(File.read(ARGV.fetch(0))).fetch("signed")
  artifact = manifest.fetch("artifact")
  version = manifest.fetch("version")
  expected_url = "https://github.com/taobaorun/keep3/releases/download/v#{version}/Keep3-#{version}.dmg"
  abort "manifest artifact URL is not immutable" unless artifact.fetch("url") == expected_url
  template = File.read(ARGV.fetch(1))
  replacements = {
    "__KEEP3_VERSION__" => version,
    "__KEEP3_SHA256__" => artifact.fetch("sha256"),
    "__KEEP3_URL__" => artifact.fetch("url")
  }
  replacements.each { |needle, value| template = template.gsub(needle, value) }
  abort "unresolved cask placeholder" if template.include?("__KEEP3_")
  File.write(ARGV.fetch(2), template)
' "$manifest" "$template" "$output" \
  || fail "could not render cask"
