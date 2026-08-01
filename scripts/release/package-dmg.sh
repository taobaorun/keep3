#!/bin/sh
set -eu

fail() {
  printf 'package-dmg: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: package-dmg.sh --app Keep3.app --version X.Y.Z --output-dir DIR

The first verified DMG becomes the canonical candidate. Re-running with the
same output directory verifies and reuses those bytes instead of rebuilding.
USAGE
  exit 64
}

app=''
version=''
output_dir=''
while test "$#" -gt 0; do
  case "$1" in
    --app) app=${2-}; shift 2 ;;
    --version) version=${2-}; shift 2 ;;
    --output-dir) output_dir=${2-}; shift 2 ;;
    --help|-h) usage ;;
    *) usage ;;
  esac
done

test -d "$app" || fail "--app must name an existing app bundle"
printf '%s\n' "$version" | /usr/bin/ruby -e '
  value = STDIN.read.strip
  exit(value.match?(/\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z/) ? 0 : 1)
' || fail "--version must be MAJOR.MINOR.PATCH"
test -n "$output_dir" || fail "--output-dir is required"
mkdir -p "$output_dir"

dmg="$output_dir/Keep3-$version.dmg"
digest_file="$dmg.sha256"
if test -e "$dmg" || test -e "$digest_file"; then
  test -f "$dmg" && test -f "$digest_file" \
    || fail "candidate DMG and digest sidecar must exist together"
  expected=$(tr -d '[:space:]' < "$digest_file")
  actual=$(shasum -a 256 "$dmg" | awk '{print $1}')
  test "$actual" = "$expected" || fail "canonical candidate digest changed"
  printf '%s\n' "$dmg"
  exit 0
fi

temporary_directory=$(mktemp -d /tmp/keep3-package-dmg-XXXXXX)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
staging="$temporary_directory/staging"
mkdir -p "$staging"
/usr/bin/ditto "$app" "$staging/Keep3.app"
ln -s /Applications "$staging/Applications"

temporary_dmg="$temporary_directory/Keep3-$version.dmg"
hdiutil create -quiet \
  -fs HFS+ \
  -format UDZO \
  -volname "Keep3 $version" \
  -srcfolder "$staging" \
  "$temporary_dmg"
test -f "$temporary_dmg" || fail "hdiutil did not produce a DMG"
mv "$temporary_dmg" "$dmg"
digest=$(shasum -a 256 "$dmg" | awk '{print $1}')
printf '%s\n' "$digest" > "$digest_file"
printf '%s\n' "$dmg"
