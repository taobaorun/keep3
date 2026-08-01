#!/bin/sh
set -eu

fail() {
  printf 'build-app: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: build-app.sh --tag vX.Y.Z --output-dir DIR [--derived-data DIR]

Builds the exact clean tag as an unsigned arm64 Release app. Developer ID and
notarization remain a separate post-funding release mode.
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
  CODE_SIGNING_ALLOWED=NO

built_app="$derived_data/Build/Products/Release/Keep3.app"
test -d "$built_app" || fail "Release app was not produced"
built_version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw \
  "$built_app/Contents/Info.plist")
test "$built_version" = "$version" \
  || fail "tag version and app version do not match"

destination="$output_dir/Keep3.app"
test ! -e "$destination" || fail "output app already exists"
/usr/bin/ditto "$built_app" "$destination"
printf '%s\n' "$destination"
