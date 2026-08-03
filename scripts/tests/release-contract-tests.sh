#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
distribution_dir="$repository_root/distribution"
release_scripts_dir="$repository_root/scripts/release"
test_directory=$(mktemp -d /tmp/keep3-release-contract-tests-XXXXXX)
mounted_test_volume=''
cleanup() {
  if test -n "$mounted_test_volume"; then
    hdiutil detach -quiet "$mounted_test_volume" >/dev/null 2>&1 || :
  fi
  rm -rf "$test_directory"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'release-contract-tests: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  test -f "$1" || fail "missing required file: ${1#$repository_root/}"
}

for contract_file in \
  release-manifest.schema.json \
  release-manifest.example.json \
  current-release.schema.json \
  current-release.example.json \
  release-status.schema.json \
  release-status.example.json \
  release-metadata-public-key.pem
do
  assert_file "$distribution_dir/$contract_file"
done

for contract_file in \
  appcast/README.md \
  homebrew/Casks/keep3.rb.template
do
  assert_file "$distribution_dir/$contract_file"
done

for release_script in \
  build-app.sh \
  package-dmg.sh \
  generate-channel-metadata.sh \
  refresh-release-status.sh \
  sign-release-metadata.sh \
  render-homebrew-cask.sh \
  validate-release.sh
do
  test -x "$release_scripts_dir/$release_script" \
    || fail "release script is missing or not executable: $release_script"
  sh -n "$release_scripts_dir/$release_script" \
    || fail "release script has invalid shell syntax: $release_script"
done

for json_file in \
  "$distribution_dir/release-manifest.schema.json" \
  "$distribution_dir/release-manifest.example.json" \
  "$distribution_dir/current-release.schema.json" \
  "$distribution_dir/current-release.example.json" \
  "$distribution_dir/release-status.schema.json" \
  "$distribution_dir/release-status.example.json"
do
  /usr/bin/ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$json_file" \
    || fail "invalid JSON: ${json_file#$repository_root/}"
done

/usr/bin/ruby -rjson -rtime -e '
  class ValidationError < StandardError; end

  def resolve_ref(root, reference)
    raise ValidationError, "external ref" unless reference.start_with?("#/")
    reference.delete_prefix("#/").split("/").reduce(root) do |value, token|
      value.fetch(token.gsub("~1", "/").gsub("~0", "~"))
    end
  end

  def valid?(schema, value, root, path = "$")
    schema = resolve_ref(root, schema.fetch("$ref")) if schema.key?("$ref")
    if schema.key?("anyOf")
      return if schema.fetch("anyOf").any? do |candidate|
        begin
          valid?(candidate, value, root, path)
          true
        rescue ValidationError
          false
        end
      end
      raise ValidationError, "#{path}: no anyOf branch matched"
    end
    expected_type = schema["type"]
    matches_type = case expected_type
                   when nil then true
                   when "object" then value.is_a?(Hash)
                   when "array" then value.is_a?(Array)
                   when "string" then value.is_a?(String)
                   when "integer" then value.is_a?(Integer)
                   when "null" then value.nil?
                   else raise ValidationError, "#{path}: unsupported type"
                   end
    raise ValidationError, "#{path}: type mismatch" unless matches_type
    raise ValidationError, "#{path}: const mismatch" if schema.key?("const") && value != schema["const"]
    raise ValidationError, "#{path}: enum mismatch" if schema.key?("enum") && !schema["enum"].include?(value)
    if value.is_a?(String)
      raise ValidationError, "#{path}: too short" if schema["minLength"] && value.length < schema["minLength"]
      raise ValidationError, "#{path}: pattern mismatch" if schema["pattern"] && !Regexp.new(schema["pattern"]).match?(value)
      Time.iso8601(value) if schema["format"] == "date-time"
    end
    if value.is_a?(Integer) && schema["minimum"] && value < schema["minimum"]
      raise ValidationError, "#{path}: below minimum"
    end
    if value.is_a?(Hash)
      Array(schema["required"]).each do |key|
        raise ValidationError, "#{path}: missing #{key}" unless value.key?(key)
      end
      properties = schema.fetch("properties", {})
      if schema["additionalProperties"] == false
        extra = value.keys - properties.keys
        raise ValidationError, "#{path}: unexpected #{extra.join(",")}" unless extra.empty?
      end
      properties.each do |key, child_schema|
        valid?(child_schema, value[key], root, "#{path}.#{key}") if value.key?(key)
      end
    end
  rescue ArgumentError => error
    raise ValidationError, "#{path}: #{error.message}"
  end

  ARGV.each_slice(2) do |schema_path, example_path|
    schema = JSON.parse(File.read(schema_path))
    example = JSON.parse(File.read(example_path))
    valid?(schema, example, schema)
  end
' \
  "$distribution_dir/release-manifest.schema.json" \
  "$distribution_dir/release-manifest.example.json" \
  "$distribution_dir/current-release.schema.json" \
  "$distribution_dir/current-release.example.json" \
  "$distribution_dir/release-status.schema.json" \
  "$distribution_dir/release-status.example.json" \
  || fail "schema examples do not validate"

/usr/bin/ruby -rjson -e '
  schema = JSON.parse(File.read(ARGV.fetch(0)))
  expected = %w[NoRelease Candidate Promoting Degraded Converged Compromised]
  states = schema.fetch("$defs").fetch("state").fetch("enum")
  abort "release status states are incomplete" unless states == expected
' "$distribution_dir/release-status.schema.json" \
  || fail "release status schema does not define the required lifecycle"

signer="$release_scripts_dir/sign-release-metadata.sh"
test -x "$signer" || fail "metadata signing script is missing or not executable"

private_key="$test_directory/metadata-private-key.pem"
public_key="$test_directory/metadata-public-key.pem"
unsigned_document="$test_directory/unsigned.json"
signed_document="$test_directory/signed.json"

"$signer" generate-fixture-key \
  --private-key "$private_key" \
  --public-key "$public_key"
test "$(stat -f '%Lp' "$private_key")" = "600" \
  || fail "fixture private key permissions are not owner-only"
grep -q 'BEGIN PUBLIC KEY' "$public_key" \
  || fail "fixture public key is not PEM encoded"
if grep -q 'PRIVATE KEY' "$distribution_dir/release-metadata-public-key.pem"; then
  fail "checked-in metadata key contains private material"
fi

sparkle_sign_update="$repository_root/.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
test -x "$sparkle_sign_update" \
  || fail "resolve Sparkle 2.9.4 before running release contract tests"
sparkle_private_key="$test_directory/sparkle-private-key"
sparkle_public_key=$(/usr/bin/ruby -rbase64 -e '
  private_pem = File.read(ARGV.fetch(0))
  public_pem = File.read(ARGV.fetch(1))
  private_der = Base64.decode64(private_pem.lines.reject { |line| line.start_with?("---") }.join)
  public_der = Base64.decode64(public_pem.lines.reject { |line| line.start_with?("---") }.join)
  File.write(ARGV.fetch(2), Base64.strict_encode64(private_der.byteslice(-32, 32)) + "\n")
  puts Base64.strict_encode64(public_der.byteslice(-32, 32))
' "$private_key" "$public_key" "$sparkle_private_key")

cat > "$unsigned_document" <<'JSON'
{
  "schemaVersion": 1,
  "signed": {
    "repository": "taobaorun/keep3",
    "keyId": "keep3-release-metadata-test"
  }
}
JSON

"$signer" sign \
  --input "$unsigned_document" \
  --output "$signed_document" \
  --private-key "$private_key" \
  --key-id keep3-release-metadata-test
"$signer" verify \
  --input "$signed_document" \
  --public-key "$public_key" \
  --expected-key-id keep3-release-metadata-test

tampered_document="$test_directory/tampered.json"
/usr/bin/ruby -rjson -e '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  document.fetch("signed")["repository"] = "attacker/keep3"
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
' "$signed_document" "$tampered_document"
if "$signer" verify \
  --input "$tampered_document" \
  --public-key "$public_key" \
  --expected-key-id keep3-release-metadata-test >/dev/null 2>&1
then
  fail "metadata signature accepted a tampered document"
fi

expect_rejected() {
  label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$label was accepted"
  fi
}

expect_rejected "non-semantic build tag" \
  "$release_scripts_dir/build-app.sh" \
  --tag 0.1.0 --output-dir "$test_directory/invalid-build"

if "$signer" sign \
  --input "$unsigned_document" \
  --output "$test_directory/missing-key.json" \
  --private-key "$test_directory/does-not-exist.pem" \
  --key-id keep3-release-metadata-test >/dev/null 2>&1
then
  fail "metadata signing accepted a missing private key"
fi

fake_app="$test_directory/Keep3.app"
mkdir -p "$fake_app/Contents/MacOS"
/usr/bin/plutil -create xml1 "$fake_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string dev.keep3.Keep3 \
  "$fake_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string 0.1.0 \
  "$fake_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string 2 \
  "$fake_app/Contents/Info.plist"
/usr/bin/plutil -insert SUFeedURL -string \
  https://taobaorun.github.io/keep3/release-channel/appcast.xml \
  "$fake_app/Contents/Info.plist"
/usr/bin/plutil -insert SUPublicEDKey -string \
  "$sparkle_public_key" \
  "$fake_app/Contents/Info.plist"
printf 'fixture executable\n' > "$fake_app/Contents/MacOS/Keep3"
chmod 755 "$fake_app/Contents/MacOS/Keep3"

expect_rejected "non-semantic package version" \
  "$release_scripts_dir/package-dmg.sh" \
  --app "$fake_app" --version 01.0.0 --output-dir "$test_directory/invalid-package"

candidate_dir="$test_directory/candidate"
dmg=$("$release_scripts_dir/package-dmg.sh" \
  --app "$fake_app" --version 0.1.0 --output-dir "$candidate_dir")
test -f "$dmg" || fail "canonical DMG was not produced"
hdiutil verify "$dmg" >/dev/null || fail "canonical DMG verification failed"
first_digest=$(shasum -a 256 "$dmg" | awk '{print $1}')
printf 'changed after canonical packaging\n' >> "$fake_app/Contents/MacOS/Keep3"
reused_dmg=$("$release_scripts_dir/package-dmg.sh" \
  --app "$fake_app" --version 0.1.0 --output-dir "$candidate_dir")
test "$reused_dmg" = "$dmg" || fail "package retry selected another candidate"
second_digest=$(shasum -a 256 "$reused_dmg" | awk '{print $1}')
test "$first_digest" = "$second_digest" \
  || fail "package retry rebuilt canonical candidate bytes"

mount_point="$test_directory/mount"
mkdir -p "$mount_point"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$mount_point" "$dmg"
mounted_test_volume=$mount_point
test -d "$mount_point/Keep3.app" || fail "DMG does not contain Keep3.app"
test -L "$mount_point/Applications" || fail "DMG does not contain Applications link"
first_launch_guide="$mount_point/首次打开 Keep3.html"
test -f "$first_launch_guide" || fail "DMG does not contain the first-launch guide"
for required_guidance in \
  '当前版本未经过 Apple Developer ID 公证' \
  '按住 Control 点击 Keep3' \
  '系统设置 → 隐私与安全性' \
  '仍要打开' \
  'https://support.apple.com/102445'
do
  grep -Fq "$required_guidance" "$first_launch_guide" \
    || fail "DMG first-launch guide is missing: $required_guidance"
done
if grep -Eiq 'xattr|--no-quarantine' "$first_launch_guide"; then
  fail "DMG first-launch guide recommends bypassing quarantine"
fi
hdiutil detach -quiet "$mount_point"
mounted_test_volume=''

sparkle_signature=$("$sparkle_sign_update" \
  --ed-key-file "$sparkle_private_key" -p "$dmg")
metadata_dir="$test_directory/metadata"
"$release_scripts_dir/generate-channel-metadata.sh" \
  --dmg "$dmg" \
  --version 0.1.0 \
  --build 2 \
  --tag v0.1.0 \
  --sequence 2 \
  --commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --sparkle-signature "$sparkle_signature" \
  --published-at 2030-01-01T00:00:00Z \
  --expires-at 2030-04-01T00:00:00Z \
  --key-id keep3-release-metadata-test \
  --output-dir "$metadata_dir" \
  --xcode-version 16.4 \
  --sdk-version macosx15.5 \
  --macos-version 15.7.7 >/dev/null

/usr/bin/ruby -rjson -rtime -e '
  manifest, current, status = ARGV.map do |path|
    JSON.parse(File.read(path)).fetch("signed")
  end
  abort "immutable manifest inherited candidate expiry" if manifest.key?("expiresAt")
  abort "stable current inherited candidate expiry" if current.key?("expiresAt")
  abort "operational status has no freshness boundary" unless status.key?("expiresAt")
  abort "operational status lifetime is not 90 days" unless
    Time.iso8601(status.fetch("expiresAt")) - Time.iso8601(status.fetch("publishedAt")) == 90 * 24 * 60 * 60
' "$metadata_dir/manifest.unsigned.json" \
  "$metadata_dir/current-release.unsigned.json" \
  "$metadata_dir/release-status.unsigned.json" \
  || fail "candidate retention leaked into stable release metadata"
"$sparkle_sign_update" --ed-key-file "$sparkle_private_key" \
  "$metadata_dir/appcast.xml" >/dev/null

xmllint --noout "$metadata_dir/appcast.xml" \
  || fail "generated appcast is not valid XML"
"$sparkle_sign_update" --ed-key-file "$sparkle_private_key" \
  --verify "$metadata_dir/appcast.xml" \
  || fail "generated appcast is not signed"
ruby -c "$metadata_dir/keep3.rb" >/dev/null \
  || fail "generated Homebrew cask is not valid Ruby"
grep -q 'depends_on macos: :sonoma' "$metadata_dir/keep3.rb" \
  || fail "generated Homebrew cask must use the supported Sonoma dependency syntax"
if grep -q 'depends_on macos: "' "$metadata_dir/keep3.rb"; then
  fail "generated Homebrew cask must not use deprecated string comparison syntax"
fi
grep -Fq 'url "https://github.com/taobaorun/keep3/releases/download/v#{version}/Keep3-#{version}.dmg"' \
  "$metadata_dir/keep3.rb" \
  || fail "generated Homebrew cask must expose a version-interpolated URL"
grep -q 'depends_on arch: :arm64' "$metadata_dir/keep3.rb" \
  || fail "generated Homebrew cask does not declare its arm64 artifact"
for required_guidance in \
  '当前版本未经过 Apple 公证' \
  '按住 Control 点击 Keep3' \
  '系统设置 > 隐私与安全性 > 仍要打开' \
  'https://taobaorun.github.io/keep3/#first-launch-guide'
do
  grep -Fq "$required_guidance" "$metadata_dir/keep3.rb" \
    || fail "generated Homebrew cask is missing first-launch guidance: $required_guidance"
done
if grep -Eiq 'xattr|--no-quarantine' "$metadata_dir/keep3.rb"; then
  fail "generated Homebrew cask bypasses quarantine"
fi

signed_manifest="$metadata_dir/manifest.json"
signed_current="$metadata_dir/current-release.json"
signed_status="$metadata_dir/release-status.json"
"$signer" sign \
  --input "$metadata_dir/manifest.unsigned.json" \
  --output "$signed_manifest" \
  --private-key "$private_key" \
  --key-id keep3-release-metadata-test
"$signer" sign \
  --input "$metadata_dir/current-release.unsigned.json" \
  --output "$signed_current" \
  --private-key "$private_key" \
  --key-id keep3-release-metadata-test
"$signer" sign \
  --input "$metadata_dir/release-status.unsigned.json" \
  --output "$signed_status" \
  --private-key "$private_key" \
  --key-id keep3-release-metadata-test

reused_manifest="$metadata_dir/manifest.reused.json"
"$signer" reuse \
  --existing "$signed_manifest" \
  --input "$metadata_dir/manifest.unsigned.json" \
  --output "$reused_manifest" \
  --public-key "$public_key" \
  --expected-key-id keep3-release-metadata-test
cmp -s "$signed_manifest" "$reused_manifest" \
  || fail "metadata retry did not preserve the existing signed bytes"

mismatched_manifest="$metadata_dir/manifest.mismatched.unsigned.json"
/usr/bin/ruby -rjson -e '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  document.fetch("signed")["build"] += 1
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
' "$metadata_dir/manifest.unsigned.json" "$mismatched_manifest"
if "$signer" reuse \
  --existing "$signed_manifest" \
  --input "$mismatched_manifest" \
  --output "$metadata_dir/manifest.invalid-reuse.json" \
  --public-key "$public_key" \
  --expected-key-id keep3-release-metadata-test >/dev/null 2>&1
then
  fail "metadata retry accepted a changed unsigned projection"
fi

stable_current_unsigned="$metadata_dir/stable-current.unsigned.json"
stable_current="$metadata_dir/stable-current.json"
/usr/bin/ruby -rjson -e '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  signed = document.fetch("signed")
  signed["sequence"] = 1
  signed["version"] = "0.0.9"
  signed["build"] = 1
  signed["tag"] = "v0.0.9"
  signed["manifestUrl"] = "https://taobaorun.github.io/keep3/release-channel/releases/v0.0.9/manifest.json"
  signed["artifactUrl"] = "https://github.com/taobaorun/keep3/releases/download/v0.0.9/Keep3-0.0.9.dmg"
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
' "$metadata_dir/current-release.unsigned.json" "$stable_current_unsigned"
"$signer" sign \
  --input "$stable_current_unsigned" \
  --output "$stable_current" \
  --private-key "$private_key" \
  --key-id keep3-release-metadata-test

validator="$release_scripts_dir/validate-release.sh"
validate_common() {
  "$validator" \
    --manifest "$1" \
    --dmg "$2" \
    --app "$3" \
    --public-key "$public_key" \
    --expected-key-id keep3-release-metadata-test \
    --tag "${4-v0.1.0}" \
    --now 2030-01-15T00:00:00Z \
    --appcast "${5-$metadata_dir/appcast.xml}" \
    --cask "${6-$metadata_dir/keep3.rb}" \
    --current "${7-$stable_current}" \
    --status "${8-$signed_status}" \
    --minimum-sequence "${9-1}" \
    --expected-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    --sparkle-sign-update "$sparkle_sign_update" \
    --sparkle-private-key "$sparkle_private_key"
}

validate_common "$signed_manifest" "$dmg" "$fake_app" >/dev/null \
  || fail "valid canonical release contract was rejected"

expect_rejected "mismatched tag" \
  validate_common "$signed_manifest" "$dmg" "$fake_app" v0.1.1

wrong_build_app="$test_directory/WrongBuild.app"
/usr/bin/ditto "$fake_app" "$wrong_build_app"
/usr/bin/plutil -replace CFBundleVersion -string 3 \
  "$wrong_build_app/Contents/Info.plist"
expect_rejected "mismatched app build" \
  validate_common "$signed_manifest" "$dmg" "$wrong_build_app"
expect_rejected "replayed sequence" \
  validate_common "$signed_manifest" "$dmg" "$fake_app" v0.1.0 \
  "$metadata_dir/appcast.xml" "$metadata_dir/keep3.rb" \
  "$stable_current" "$signed_status" 2

non_monotonic_current="$metadata_dir/non-monotonic-current.json"
"$signer" sign \
  --input "$metadata_dir/current-release.unsigned.json" \
  --output "$non_monotonic_current" \
  --private-key "$private_key" \
  --key-id keep3-release-metadata-test
expect_rejected "non-monotonic current build" \
  validate_common "$signed_manifest" "$dmg" "$fake_app" v0.1.0 \
  "$metadata_dir/appcast.xml" "$metadata_dir/keep3.rb" \
  "$non_monotonic_current"

tampered_dmg_dir="$test_directory/tampered-dmg"
mkdir -p "$tampered_dmg_dir"
/usr/bin/ditto "$dmg" "$tampered_dmg_dir/Keep3-0.1.0.dmg"
printf 'tamper\n' >> "$tampered_dmg_dir/Keep3-0.1.0.dmg"
expect_rejected "changed DMG bytes" \
  validate_common "$signed_manifest" \
  "$tampered_dmg_dir/Keep3-0.1.0.dmg" "$fake_app"

resign_variant() {
  source_document=$1
  output_document=$2
  mutation=$3
  unsigned_variant="$output_document.unsigned"
  /usr/bin/ruby -rjson -e "$mutation" "$source_document" "$unsigned_variant"
  "$signer" sign \
    --input "$unsigned_variant" \
    --output "$output_document" \
    --private-key "$private_key" \
    --key-id keep3-release-metadata-test
}

converged_status="$metadata_dir/converged-status.json"
resign_variant "$metadata_dir/release-status.unsigned.json" "$converged_status" '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  signed = document.fetch("signed")
  signed["state"] = "Converged"
  signed["currentManifestUrl"] = signed.fetch("candidateManifestUrl")
  signed["message"] = "All release channels agree."
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
'
refreshed_status="$metadata_dir/refreshed-status.json"
"$release_scripts_dir/refresh-release-status.sh" \
  --current "$signed_current" \
  --status "$converged_status" \
  --public-key "$public_key" \
  --expected-key-id keep3-release-metadata-test \
  --private-key "$private_key" \
  --published-at 2030-02-01T00:00:00Z \
  --expires-at 2030-05-02T00:00:00Z \
  --output "$refreshed_status" >/dev/null
"$signer" verify --input "$refreshed_status" --public-key "$public_key" \
  --expected-key-id keep3-release-metadata-test >/dev/null \
  || fail "refreshed operational status has an invalid signature"
/usr/bin/ruby -rjson -e '
  previous, refreshed = ARGV.map { |path| JSON.parse(File.read(path)).fetch("signed") }
  abort "status refresh did not advance its sequence" unless
    refreshed["sequence"] == previous.fetch("sequence") + 1
  abort "status refresh changed the release identity" unless
    %w[version build tag trustState candidateManifestUrl currentManifestUrl].all? do |field|
      refreshed[field] == previous[field]
    end
  abort "status refresh has unexpected timestamps" unless
    refreshed["publishedAt"] == "2030-02-01T00:00:00Z" &&
      refreshed["expiresAt"] == "2030-05-02T00:00:00Z"
' "$converged_status" "$refreshed_status" \
  || fail "release status refresh changed stable discovery"

refresh_compromised="$metadata_dir/refresh-compromised.json"
resign_variant "$metadata_dir/release-status.unsigned.json" "$refresh_compromised" '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  document.fetch("signed")["state"] = "Compromised"
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
'
expect_rejected "Compromised status refresh" \
  "$release_scripts_dir/refresh-release-status.sh" \
  --current "$signed_current" \
  --status "$refresh_compromised" \
  --public-key "$public_key" \
  --expected-key-id keep3-release-metadata-test \
  --private-key "$private_key" \
  --published-at 2030-02-01T00:00:00Z \
  --expires-at 2030-05-02T00:00:00Z \
  --output "$metadata_dir/forbidden-refresh.json"

wrong_checksum="$metadata_dir/wrong-checksum.json"
resign_variant "$metadata_dir/manifest.unsigned.json" "$wrong_checksum" '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  document.fetch("signed").fetch("artifact")["sha256"] = "c" * 64
  document.fetch("signed").fetch("provenance")["candidateDigest"] = "c" * 64
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
'
expect_rejected "wrong checksum" \
  validate_common "$wrong_checksum" "$dmg" "$fake_app"

expiring_manifest="$metadata_dir/expiring-manifest.json"
resign_variant "$metadata_dir/manifest.unsigned.json" "$expiring_manifest" '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  document.fetch("signed")["expiresAt"] = "2030-01-10T00:00:00Z"
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
'
expect_rejected "expiring immutable manifest" \
  validate_common "$expiring_manifest" "$dmg" "$fake_app"

expired_status="$metadata_dir/expired-status.json"
resign_variant "$metadata_dir/release-status.unsigned.json" "$expired_status" '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  document.fetch("signed")["expiresAt"] = "2030-01-10T00:00:00Z"
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
'
expect_rejected "expired operational status" \
  validate_common "$signed_manifest" "$dmg" "$fake_app" v0.1.0 \
  "$metadata_dir/appcast.xml" "$metadata_dir/keep3.rb" \
  "$stable_current" "$expired_status"

mutable_url_manifest="$metadata_dir/mutable-url.json"
resign_variant "$metadata_dir/manifest.unsigned.json" "$mutable_url_manifest" '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  document.fetch("signed").fetch("artifact")["url"] = "https://github.com/taobaorun/keep3/releases/latest/download/Keep3.dmg"
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
'
expect_rejected "mutable artifact URL" \
  validate_common "$mutable_url_manifest" "$dmg" "$fake_app"

wrong_source_manifest="$metadata_dir/wrong-source.json"
resign_variant "$metadata_dir/manifest.unsigned.json" "$wrong_source_manifest" '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  document.fetch("signed").fetch("source")["tagUrl"] = "https://example.com/v0.1.0"
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
'
expect_rejected "wrong source link" \
  validate_common "$wrong_source_manifest" "$dmg" "$fake_app"

unknown_status="$metadata_dir/unknown-status.json"
resign_variant "$metadata_dir/release-status.unsigned.json" "$unknown_status" '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  document.fetch("signed")["state"] = "Unknown"
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
'
expect_rejected "unknown operational state" \
  validate_common "$signed_manifest" "$dmg" "$fake_app" v0.1.0 \
  "$metadata_dir/appcast.xml" "$metadata_dir/keep3.rb" \
  "$stable_current" "$unknown_status"

compromised_status="$metadata_dir/compromised-status.json"
resign_variant "$metadata_dir/release-status.unsigned.json" "$compromised_status" '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  document.fetch("signed")["state"] = "Compromised"
  File.write(ARGV.fetch(1), JSON.pretty_generate(document) + "\n")
'
expect_rejected "compromised channel state" \
  validate_common "$signed_manifest" "$dmg" "$fake_app" v0.1.0 \
  "$metadata_dir/appcast.xml" "$metadata_dir/keep3.rb" \
  "$stable_current" "$compromised_status"

fixture_key_app="$test_directory/FixtureKey.app"
/usr/bin/ditto "$fake_app" "$fixture_key_app"
/usr/bin/plutil -replace SUPublicEDKey -string \
  eRFPLZuNM6m8bltmtpPX4fzKbufI1z6rKJHtgIIsllk= \
  "$fixture_key_app/Contents/Info.plist"
expect_rejected "production Sparkle fixture key" \
  validate_common "$signed_manifest" "$dmg" "$fixture_key_app"

bad_appcast="$metadata_dir/bad-appcast.xml"
/usr/bin/ruby -e '
  value = File.read(ARGV.fetch(0)).sub("https://github.com/taobaorun/keep3", "https://example.com")
  File.write(ARGV.fetch(1), value)
' "$metadata_dir/appcast.xml" "$bad_appcast"
expect_rejected "stale appcast projection" \
  validate_common "$signed_manifest" "$dmg" "$fake_app" v0.1.0 \
  "$bad_appcast"

bad_cask="$metadata_dir/bad-cask.rb"
/usr/bin/ruby -e '
  value = File.read(ARGV.fetch(0)).sub(/sha256 "[0-9a-f]+"/, "sha256 :no_check")
  File.write(ARGV.fetch(1), value)
' "$metadata_dir/keep3.rb" "$bad_cask"
expect_rejected "unsafe Homebrew projection" \
  validate_common "$signed_manifest" "$dmg" "$fake_app" v0.1.0 \
  "$metadata_dir/appcast.xml" "$bad_cask"

git -C "$repository_root" check-ignore -q distribution/generated/example \
  || fail "generated distribution output is not ignored"
git -C "$repository_root" check-ignore -q distribution/private/key.pem \
  || fail "private distribution material is not ignored"
printf 'release-contract-tests: passed\n'
