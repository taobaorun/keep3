#!/bin/sh
set -eu

fail() {
  printf 'build-app: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: build-app.sh --tag vX.Y.Z --output-dir DIR [--derived-data DIR]

Builds the exact clean tag as an ad-hoc-signed arm64 Release app. Developer ID
and notarization remain a separate post-funding release mode.
USAGE
  exit 64
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
tag=''
output_dir=''
derived_data="$repository_root/.build/release/DerivedData"

while test "$#" -gt 0; do
  case "$1" in
    --tag) tag=${2-}; shift 2 ;;
    --output-dir) output_dir=${2-}; shift 2 ;;
    --derived-data) derived_data=${2-}; shift 2 ;;
    --help|-h) usage ;;
    *) usage ;;
  esac
done

printf '%s\n' "$tag" | /usr/bin/ruby -e '
  value = STDIN.read.strip
  exit(value.match?(/\Av(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z/) ? 0 : 1)
' || fail "--tag must be vMAJOR.MINOR.PATCH"
test -n "$output_dir" || fail "--output-dir is required"

version=${tag#v}
head_commit=$(git -C "$repository_root" rev-parse HEAD)
tag_commit=$(git -C "$repository_root" rev-parse "refs/tags/$tag^{commit}" 2>/dev/null) \
  || fail "tag does not exist: $tag"
test "$head_commit" = "$tag_commit" || fail "HEAD is not the requested tag"
git -C "$repository_root" diff --quiet || fail "tracked working tree is dirty"
git -C "$repository_root" diff --cached --quiet || fail "index is dirty"
test -z "$(git -C "$repository_root" ls-files --others --exclude-standard)" \
  || fail "untracked files are present"

mkdir -p "$output_dir" "$derived_data"
xcodebuild build \
  -project "$repository_root/Keep3.xcodeproj" \
  -scheme Keep3 \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=-

built_app="$derived_data/Build/Products/Release/Keep3.app"
test -d "$built_app" || fail "Release app was not produced"
built_version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw \
  "$built_app/Contents/Info.plist")
test "$built_version" = "$version" \
  || fail "tag version and app version do not match"

ad_hoc_entitlements="$repository_root/Keep3/Keep3AdHoc.entitlements"
test -f "$ad_hoc_entitlements" || fail "ad-hoc entitlements are missing"

helper="$built_app/Contents/XPCServices/Keep3MediaService.xpc"
test -d "$helper" || fail "MediaRemote helper was not embedded"
/usr/bin/codesign --force --sign - --options runtime "$helper" \
  || fail "MediaRemote helper could not be hardened for ad-hoc distribution"
helper_details=$(/usr/bin/codesign -dv --verbose=4 "$helper" 2>&1) \
  || fail "MediaRemote helper signature could not be inspected"
helper_identifier=$(printf '%s\n' "$helper_details" \
  | /usr/bin/sed -n 's/^Identifier=//p')
test "$helper_identifier" = "com.apple.controlcenter.Keep3MediaService" \
  || fail "MediaRemote helper signature has the wrong identifier: $helper_identifier"
printf '%s\n' "$helper_details" \
  | /usr/bin/grep -Eq '^CodeDirectory .*flags=.*runtime' \
  || fail "MediaRemote helper is missing hardened runtime"
helper_entitlements=$(/usr/bin/codesign -d --entitlements - "$helper" 2>/dev/null) \
  || fail "MediaRemote helper entitlements could not be inspected"
test -z "$helper_entitlements" \
  || fail "MediaRemote helper has unexpected entitlements"

/usr/bin/codesign --force --sign - --options runtime \
  --entitlements "$ad_hoc_entitlements" "$built_app" \
  || fail "Release app could not be finalized for ad-hoc distribution"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$built_app" \
  || fail "Release app does not have a valid complete signature"
app_details=$(/usr/bin/codesign -dv --verbose=4 "$built_app" 2>&1) \
  || fail "Release app signature could not be inspected"
app_identifier=$(printf '%s\n' "$app_details" \
  | /usr/bin/sed -n 's/^Identifier=//p')
test "$app_identifier" = "dev.keep3.Keep3" \
  || fail "Release app signature has the wrong identifier: $app_identifier"
printf '%s\n' "$app_details" \
  | /usr/bin/grep -Eq '^CodeDirectory .*flags=.*runtime' \
  || fail "Release app is missing hardened runtime"

signature_audit_dir="$derived_data/Keep3SignatureAudit"
mkdir -p "$signature_audit_dir"
signed_entitlements="$signature_audit_dir/signed-entitlements.plist"
signed_entitlements_output=$(
  /usr/bin/codesign -d --entitlements :- "$built_app" 2>&1
) || fail "Release app entitlements could not be inspected"
printf '%s\n' "$signed_entitlements_output" \
  | /usr/bin/sed -n '/^<?xml/,/<\/plist>$/p' > "$signed_entitlements"
/usr/bin/plutil -lint "$signed_entitlements" >/dev/null \
  || fail "Release app entitlements are not a valid property list"
expected_entitlements_binary="$signature_audit_dir/expected-entitlements.binary"
signed_entitlements_binary="$signature_audit_dir/signed-entitlements.binary"
/usr/bin/plutil -convert binary1 -o "$expected_entitlements_binary" \
  "$ad_hoc_entitlements"
/usr/bin/plutil -convert binary1 -o "$signed_entitlements_binary" \
  "$signed_entitlements"
/usr/bin/cmp -s "$expected_entitlements_binary" "$signed_entitlements_binary" \
  || fail "Release app has unexpected entitlements"

destination="$output_dir/Keep3.app"
test ! -e "$destination" || fail "output app already exists"
/usr/bin/ditto "$built_app" "$destination"
printf '%s\n' "$destination"
