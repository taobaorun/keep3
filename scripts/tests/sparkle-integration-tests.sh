#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
fixtures_dir="$repository_root/Keep3Tests/Fixtures/Updates"
resolved_file="$repository_root/Keep3.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
sparkle_artifacts="$repository_root/.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle"
sign_update="$sparkle_artifacts/bin/sign_update"

fail() {
  printf 'sparkle-integration-tests: %s\n' "$1" >&2
  exit 1
}

test "$(plutil -extract pins.0.state.version raw "$resolved_file")" = "2.9.4" \
  || fail "Sparkle must resolve to 2.9.4"
test "$(plutil -extract pins.0.state.revision raw "$resolved_file")" = \
  "b6496a74a087257ef5e6da1c5b29a447a60f5bd7" \
  || fail "Sparkle revision does not match the 2.9.4 pin"
test -x "$sign_update" \
  || fail "resolve packages before running this test so sign_update is available"

for fixture in no-update valid-update invalid-signature; do
  xmllint --noout "$fixtures_dir/appcasts/$fixture.xml" \
    || fail "$fixture.xml is not well-formed XML"
done

xml_namespace='http://www.andymatuschak.org/xml-namespaces/sparkle'
installed_build=$(xmllint --xpath \
  "string(//*[local-name()='version' and namespace-uri()='$xml_namespace'])" \
  "$fixtures_dir/appcasts/no-update.xml")
candidate_build=$(xmllint --xpath \
  "string(//*[local-name()='version' and namespace-uri()='$xml_namespace'])" \
  "$fixtures_dir/appcasts/valid-update.xml")
invalid_build=$(xmllint --xpath \
  "string(//*[local-name()='version' and namespace-uri()='$xml_namespace'])" \
  "$fixtures_dir/appcasts/invalid-signature.xml")
test "$installed_build" -eq 1 || fail "installed fixture build must be 1"
test "$candidate_build" -gt "$installed_build" \
  || fail "candidate fixture build must increase monotonically"
test "$invalid_build" -eq "$candidate_build" \
  || fail "invalid-signature fixture must isolate signature handling"

temporary_directory=$(mktemp -d /tmp/keep3-sparkle-tests-XXXXXX)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
archive="$temporary_directory/Keep3-0.2.0.dmg"
feed="$temporary_directory/appcast.xml"
printf 'Keep3 unsigned update fixture\nversion=0.2.0\nbuild=2\n' > "$archive"
cp "$fixtures_dir/appcasts/valid-update.xml" "$feed"

# This is Sparkle's public TestApplication fixture key (private+public old
# format), not a Keep3 release credential. It is intentionally non-secret.
sparkle_public_test_key='yO6HVAq9A8E90MsehS8MFhM0/GNuzdFe15DJRhuio2wApES44l15x6wRGkBZROgpAhr1r56lKjcFYQjz+6RdCXkRTy2bjTOpvG5bZraT1+H8ym7nyNc+qyiR7YCCLJZZ'

archive_signature=$(printf '%s\n' "$sparkle_public_test_key" \
  | "$sign_update" --ed-key-file - -p "$archive")
printf '%s\n' "$sparkle_public_test_key" \
  | "$sign_update" --ed-key-file - --verify "$archive" "$archive_signature"

printf 'tampered\n' >> "$archive"
if printf '%s\n' "$sparkle_public_test_key" \
  | "$sign_update" --ed-key-file - --verify "$archive" "$archive_signature" \
    >/dev/null 2>&1
then
  fail "Sparkle accepted a modified archive"
fi

printf '%s\n' "$sparkle_public_test_key" \
  | "$sign_update" --ed-key-file - "$feed" >/dev/null
printf '%s\n' "$sparkle_public_test_key" \
  | "$sign_update" --ed-key-file - --verify "$feed"
tampered_feed="$temporary_directory/tampered-appcast.xml"
sed 's/Keep3 0\.2\.0/Keep3 9.9.9/' "$feed" > "$tampered_feed"
if printf '%s\n' "$sparkle_public_test_key" \
  | "$sign_update" --ed-key-file - --verify "$tampered_feed" \
    >/dev/null 2>&1
then
  fail "Sparkle accepted a modified signed appcast"
fi

if rg -n 'feedParameters|httpHeaders|URLRequest|URLSession|analytics|donor' \
  "$repository_root/Keep3/Updates" >/dev/null
then
  fail "Keep3's update boundary adds non-release request payloads"
fi

printf 'sparkle-integration-tests: passed\n'
