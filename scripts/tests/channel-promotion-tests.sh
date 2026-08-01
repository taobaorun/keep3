#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
workflows_dir="$repository_root/.github/workflows"
release_scripts_dir="$repository_root/scripts/release"
docs_dir="$repository_root/docs/distribution"
test_directory=$(mktemp -d /tmp/keep3-channel-promotion-tests-XXXXXX)
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

fail() {
  printf 'channel-promotion-tests: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  test -f "$1" || fail "missing required file: ${1#$repository_root/}"
}

for required_file in \
  "$workflows_dir/ci.yml" \
  "$workflows_dir/release-candidate.yml" \
  "$workflows_dir/promote-release.yml" \
  "$docs_dir/release-runbook.md" \
  "$docs_dir/update-key-incident-runbook.md"
do
  assert_file "$required_file"
done

for release_script in publish-release-channel.sh probe-channels.sh; do
  test -x "$release_scripts_dir/$release_script" \
    || fail "$release_script is missing or not executable"
  sh -n "$release_scripts_dir/$release_script" \
    || fail "$release_script has invalid shell syntax"
done

if rg -n --pcre2 'uses:\s*[^\s]+@(?![0-9a-f]{40}(?:\s|$))' \
  "$workflows_dir" >/dev/null
then
  fail "every GitHub action must be pinned to a full commit SHA"
fi

ci_workflow="$workflows_dir/ci.yml"
candidate_workflow="$workflows_dir/release-candidate.yml"
promotion_workflow="$workflows_dir/promote-release.yml"

rg -q '^permissions:$' "$ci_workflow" \
  || fail "CI must declare workflow permissions"
rg -q '^  contents: read$' "$ci_workflow" \
  || fail "CI must be contents-read-only"
if rg -n 'secrets\.|gh release|git push|pages|homebrew' "$ci_workflow" >/dev/null; then
  fail "ordinary CI contains a publication capability"
fi

rg -q 'tags:' "$candidate_workflow" \
  || fail "candidate workflow is not tag-triggered"
rg -q 'attest-build-provenance' "$candidate_workflow" \
  || fail "candidate workflow does not attest canonical bytes"
rg -q 'attestation.json' "$candidate_workflow" \
  || fail "candidate workflow does not attest its provenance receipt"
rg -q 'upload-artifact' "$candidate_workflow" \
  || fail "candidate workflow does not preserve the candidate"
if rg -n 'secrets\.|gh release|git push|release-production' \
  "$candidate_workflow" >/dev/null
then
  fail "tag candidate workflow can access publication capabilities"
fi
if rg -n 'sparkle-signature|KEEP3_.*PRIVATE|generate-channel-metadata' \
  "$candidate_workflow" >/dev/null
then
  fail "credential-free candidate workflow attempts to sign release metadata"
fi

rg -q 'workflow_dispatch:' "$promotion_workflow" \
  || fail "promotion must require explicit dispatch"
rg -q '^  preflight:$' "$promotion_workflow" \
  || fail "promotion lacks a credential-free preflight job"
rg -q '^  promote:$' "$promotion_workflow" \
  || fail "promotion lacks a protected promotion job"
rg -q 'needs: preflight' "$promotion_workflow" \
  || fail "protected promotion does not depend on preflight"
rg -q 'environment: release-production' "$promotion_workflow" \
  || fail "promotion is not protected by the release environment"
rg -q 'ref: main' "$promotion_workflow" \
  || fail "promotion does not run trusted main tooling"
rg -q 'merge-base --is-ancestor' "$promotion_workflow" \
  || fail "promotion does not prove tag reachability from main"
rg -q 'gh attestation verify' "$promotion_workflow" \
  || fail "promotion does not verify candidate provenance"
for provenance_policy in \
  '--source-digest "$tag_commit"' \
  '--source-ref "refs/tags/$tag"' \
  '--signer-workflow "$signer_workflow"' \
  '--signer-digest "$tag_commit"' \
  '--deny-self-hosted-runners'
do
  rg -Fq -- "$provenance_policy" "$promotion_workflow" \
    || fail "promotion does not bind attestation policy: $provenance_policy"
done
rg -q 'gh run view.*candidate_run_id' "$promotion_workflow" \
  || fail "promotion does not verify the selected candidate workflow run"
rg -q 'run_head_sha=' "$promotion_workflow" && rg -q 'headSha' "$promotion_workflow" \
  || fail "promotion does not read the selected run head SHA"
rg -q 'test.*run_head_sha.*tag_commit' "$promotion_workflow" \
  || fail "promotion does not bind the selected run to the tag commit"
rg -q 'strict-monotonic' "$promotion_workflow" \
  || fail "promotion does not enforce strict build monotonicity"
rg -q 'hdiutil attach' "$promotion_workflow" \
  || fail "promotion does not validate the app inside the attested DMG"
rg -q 'appcast.xml.*>/dev/null' "$promotion_workflow" \
  || fail "promotion does not sign the required Sparkle feed"
rg -q 'unexpected channel response' "$promotion_workflow" \
  || fail "promotion does not fail closed on channel read errors"
for required_command in \
  generate-channel-metadata.sh \
  sign-release-metadata.sh \
  validate-release.sh \
  publish-release-channel.sh
do
  rg -q "$required_command" "$promotion_workflow" \
    || fail "protected promotion does not invoke $required_command"
done
rg -q '" gh-pages' "$release_scripts_dir/publish-release-channel.sh" \
  || fail "release channel publication does not target the Pages branch"
rg -q 'gh pr create' "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew promotion does not stage a candidate PR"
rg -q 'gh pr merge' "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew promotion does not merge the verified candidate PR"
rg -q -- '--force-with-lease' "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew candidate branch updates are not race-safe"
rg -q -- '--match-head-commit' "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew merge is not pinned to the verified PR head"
rg -q 'headRefOid' "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew promotion does not inspect the remote PR head"
rg -Fq 'paths == ["Casks/keep3.rb"]' \
  "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew promotion does not constrain the candidate file set"
if rg -n 'publish-release-channel\.sh --help|release-runbook\.md >/dev/null' \
  "$promotion_workflow" >/dev/null
then
  fail "protected promotion still contains non-executable scaffolding"
fi

expect_rejected() {
  label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$label was accepted"
  fi
}

source_repository="$test_directory/source"
git init -q -b main "$source_repository"
git -C "$source_repository" config user.name 'Keep3 Release Test'
git -C "$source_repository" config user.email 'release-test@keep3.invalid'
printf 'protected main\n' > "$source_repository/README.md"
git -C "$source_repository" add README.md
git -C "$source_repository" commit -q -m 'Protected release source'
git -C "$source_repository" tag v1.0.0
release_commit=$(git -C "$source_repository" rev-parse HEAD)
git -C "$source_repository" switch -q -c side
printf 'off branch\n' > "$source_repository/side.txt"
git -C "$source_repository" add side.txt
git -C "$source_repository" commit -q -m 'Off-branch tag'
git -C "$source_repository" tag v1.1.0
git -C "$source_repository" switch -q main

candidate="$test_directory/candidate"
mkdir -p "$candidate"
dmg="$candidate/Keep3-1.0.0.dmg"
printf 'canonical Keep3 candidate bytes\n' > "$dmg"
candidate_digest=$(shasum -a 256 "$dmg" | awk '{print $1}')
printf '%s\n' "$candidate_digest" > "$dmg.sha256"

key_id='keep3-release-metadata-test'
private_key="$test_directory/metadata-private.pem"
public_key="$test_directory/metadata-public.pem"
signer="$release_scripts_dir/sign-release-metadata.sh"
"$signer" generate-fixture-key \
  --private-key "$private_key" --public-key "$public_key"

/usr/bin/ruby -rjson -e '
  directory, digest, commit, key_id = ARGV
  artifact_url = "https://github.com/taobaorun/keep3/releases/download/v1.0.0/Keep3-1.0.0.dmg"
  manifest_url = "https://taobaorun.github.io/keep3/release-channel/releases/v1.0.0/manifest.json"
  common = {
    "repository" => "taobaorun/keep3",
    "canonicalOrigin" => "https://taobaorun.github.io",
    "sequence" => 2,
    "version" => "1.0.0",
    "build" => 2,
    "tag" => "v1.0.0",
    "trustState" => "unsigned",
    "publishedAt" => "2030-01-01T00:00:00Z",
    "expiresAt" => "2030-02-01T00:00:00Z",
    "keyId" => key_id
  }
  manifest = {
    "schemaVersion" => 1,
    "signed" => common.merge(
      "artifact" => {
        "fileName" => "Keep3-1.0.0.dmg", "url" => artifact_url,
        "sha256" => digest, "size" => 32,
        "sparkleEdSignature" => "A" * 86 + "=="
      },
      "source" => {
        "tagUrl" => "https://github.com/taobaorun/keep3/tree/v1.0.0",
        "archiveUrl" => "https://github.com/taobaorun/keep3/archive/refs/tags/v1.0.0.tar.gz",
        "commit" => commit
      },
      "channels" => {
        "manifestUrl" => manifest_url,
        "appcastUrl" => "https://taobaorun.github.io/keep3/release-channel/appcast.xml",
        "homebrewTap" => "taobaorun/keep3",
        "homebrewCaskPath" => "Casks/keep3.rb"
      },
      "provenance" => { "gitCommit" => commit, "candidateDigest" => digest }
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
  %w[Promoting Degraded Converged].each do |state|
    status = {
      "schemaVersion" => 1,
      "signed" => common.merge(
        "state" => state, "candidateManifestUrl" => manifest_url,
        "currentManifestUrl" => state == "Converged" ? manifest_url : nil,
        "message" => "fixture #{state}",
        "fallbackUrl" => "https://github.com/taobaorun/keep3/releases"
      )
    }
    name = "release-status-#{state.downcase}.unsigned.json"
    File.write(File.join(directory, name), JSON.pretty_generate(status) + "\n")
  end
  previous = {
    "schemaVersion" => 1,
    "signed" => common.merge(
      "sequence" => 1, "version" => "0.9.0", "build" => 1,
      "tag" => "v0.9.0", "state" => "Converged"
    )
  }
  stale = {
    "schemaVersion" => 1,
    "signed" => common.merge("sequence" => 1, "state" => "Converged")
  }
  compromised = {
    "schemaVersion" => 1,
    "signed" => common.merge("sequence" => 3, "state" => "Compromised")
  }
  {
    "manifest.unsigned.json" => manifest,
    "current-release.unsigned.json" => current,
    "previous-current.unsigned.json" => previous,
    "stale-current.unsigned.json" => stale,
    "compromised.unsigned.json" => compromised
  }.each do |name, document|
    File.write(File.join(directory, name), JSON.pretty_generate(document) + "\n")
  end
' "$candidate" "$candidate_digest" "$release_commit" "$key_id"

for name in manifest current-release \
  release-status-promoting release-status-degraded release-status-converged
do
  "$signer" sign \
    --input "$candidate/$name.unsigned.json" \
    --output "$candidate/$name.json" \
    --private-key "$private_key" --key-id "$key_id"
done
for name in previous-current stale-current compromised; do
  "$signer" sign \
    --input "$candidate/$name.unsigned.json" \
    --output "$test_directory/$name.json" \
    --private-key "$private_key" --key-id "$key_id"
done

artifact_url='https://github.com/taobaorun/keep3/releases/download/v1.0.0/Keep3-1.0.0.dmg'
cat > "$candidate/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="$artifact_url" sparkle:version="2" sparkle:shortVersionString="1.0.0" /></item></channel></rss>
XML
cat > "$candidate/keep3.rb" <<RUBY
cask "keep3" do
  version "1.0.0"
  sha256 "$candidate_digest"
  url "$artifact_url"
  app "Keep3.app"
end
RUBY
/usr/bin/ruby -rjson -e '
  receipt = {
    "repository" => "taobaorun/keep3", "tag" => "v1.0.0",
    "commit" => ARGV.fetch(0), "build" => 2, "sha256" => ARGV.fetch(1)
  }
  File.write(ARGV.fetch(2), JSON.pretty_generate(receipt) + "\n")
' "$release_commit" "$candidate_digest" "$candidate/attestation.json"

publisher="$release_scripts_dir/publish-release-channel.sh"
run_publisher() {
  candidate_path=$1
  remote_path=$2
  state_path=$3
  release_tag=$4
  previous_path=$5
  incident_path=$6
  shift 6
  if test -n "$previous_path"; then
    set -- --previous-current "$previous_path" "$@"
    if test -n "$incident_path"; then
      set -- --operational-status "$incident_path" "$@"
    fi
  fi
  "$publisher" --mode fixture --repository-root "$repository_root" \
    --source-repository "$source_repository" --protected-ref main \
    --tag "$release_tag" --candidate-dir "$candidate_path" \
    --attestation "$candidate_path/attestation.json" \
    --metadata-public-key "$public_key" --metadata-key-id "$key_id" \
    --state-dir "$state_path" --channel-root "$remote_path" "$@"
}

expect_rejected "off-main release tag" run_publisher \
  "$candidate" "$test_directory/off-main-remote" "$test_directory/off-main-state" \
  v1.1.0 "$test_directory/previous-current.json" '' --preflight-only
test ! -e "$test_directory/off-main-remote" \
  || fail "off-main preflight wrote a public channel"

tampered_candidate="$test_directory/tampered-candidate"
/usr/bin/ditto "$candidate" "$tampered_candidate"
printf 'tampered\n' >> "$tampered_candidate/Keep3-1.0.0.dmg"
expect_rejected "changed canonical candidate" run_publisher \
  "$tampered_candidate" "$test_directory/tampered-remote" "$test_directory/tampered-state" \
  v1.0.0 "$test_directory/previous-current.json" '' --preflight-only
test ! -e "$test_directory/tampered-remote" \
  || fail "digest preflight wrote a public channel"

expect_rejected "non-increasing candidate build" run_publisher \
  "$candidate" "$test_directory/stale-remote" "$test_directory/stale-state" \
  v1.0.0 "$test_directory/stale-current.json" '' --preflight-only
test ! -e "$test_directory/stale-remote" \
  || fail "monotonicity preflight wrote a public channel"

expect_rejected "Compromised operational state" run_publisher \
  "$candidate" "$test_directory/compromised-remote" "$test_directory/compromised-state" \
  v1.0.0 "$test_directory/previous-current.json" "$test_directory/compromised.json"
test ! -e "$test_directory/compromised-remote" \
  || fail "Compromised state allowed a public write"

remote="$test_directory/remote"
promotion_state="$test_directory/promotion-state"
expect_rejected "injected failure after tap" run_publisher \
  "$candidate" "$remote" "$promotion_state" v1.0.0 \
  "$test_directory/previous-current.json" '' --fail-after tap
test -f "$remote/github/releases/v1.0.0/stable" \
  || fail "GitHub did not become stable before the injected failure"
test -f "$remote/tap/Casks/keep3.rb" \
  || fail "tap was not written before the injected failure"
test ! -f "$remote/pages/release-channel/appcast.xml" \
  || fail "appcast advanced after an earlier tap failure"
test ! -f "$remote/pages/release-channel/current-release.json" \
  || fail "current moved before convergence"
test "$(/usr/bin/ruby -rjson -e \
  'puts JSON.parse(File.read(ARGV[0])).dig("signed", "state")' \
  "$remote/pages/release-channel/release-status.json")" = Degraded \
  || fail "partial public failure was not recorded as Degraded"

run_publisher "$candidate" "$remote" "$promotion_state" v1.0.0 \
  "$test_directory/previous-current.json" '' >/dev/null
"$release_scripts_dir/probe-channels.sh" \
  --mode fixture --tag v1.0.0 --version 1.0.0 --build 2 \
  --sha256 "$candidate_digest" --dmg-name Keep3-1.0.0.dmg \
  --manifest "$candidate/manifest.json" --appcast "$candidate/appcast.xml" \
  --cask "$candidate/keep3.rb" --channel-root "$remote" \
  --require-current >/dev/null

/usr/bin/ruby -e '
  events = File.readlines(ARGV.fetch(0), chomp: true)
  positions = %w[github tap appcast probe current converged].to_h do |step|
    [step, events.index(step) || abort("missing #{step}")]
  end
  abort "publication order changed" unless positions.values == positions.values.sort
  degraded = events.index("status:Degraded") || abort("missing Degraded")
  abort "current moved before degraded recovery" unless degraded < positions.fetch("appcast")
' "$promotion_state/events.log" || fail "promotion event order is unsafe"

events_before=$(shasum -a 256 "$promotion_state/events.log" | awk '{print $1}')
asset_before=$(shasum -a 256 "$remote/github/releases/v1.0.0/Keep3-1.0.0.dmg" | awk '{print $1}')
run_publisher "$candidate" "$remote" "$promotion_state" v1.0.0 \
  "$test_directory/previous-current.json" '' >/dev/null
test "$events_before" = "$(shasum -a 256 "$promotion_state/events.log" | awk '{print $1}')" \
  || fail "converged retry repeated publication events"
test "$asset_before" = "$(shasum -a 256 "$remote/github/releases/v1.0.0/Keep3-1.0.0.dmg" | awk '{print $1}')" \
  || fail "converged retry changed canonical asset bytes"

printf '\n# stale checksum\n' >> "$remote/tap/Casks/keep3.rb"
expect_rejected "stale remote cask" \
  "$release_scripts_dir/probe-channels.sh" \
  --mode fixture --tag v1.0.0 --version 1.0.0 --build 2 \
  --sha256 "$candidate_digest" --dmg-name Keep3-1.0.0.dmg \
  --manifest "$candidate/manifest.json" --appcast "$candidate/appcast.xml" \
  --cask "$candidate/keep3.rb" --channel-root "$remote"

printf 'channel-promotion-tests: passed\n'
