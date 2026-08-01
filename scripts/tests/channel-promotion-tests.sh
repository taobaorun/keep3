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
  "$workflows_dir/refresh-release-status.yml" \
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

/usr/bin/ruby -e '
  Dir.glob(File.join(ARGV.fetch(0), "**", "*.{yml,yaml}")).each do |path|
    File.foreach(path).with_index(1) do |line, number|
      match = line.match(/^\s*uses:\s*(\S+)/)
      next unless match
      next if match[1].match?(/@[0-9a-f]{40}\z/)
      warn "#{path}:#{number}: action is not pinned to a full commit SHA"
      exit 1
    end
  end
' "$workflows_dir" \
  || fail "every GitHub action must be pinned to a full commit SHA"

ci_workflow="$workflows_dir/ci.yml"
candidate_workflow="$workflows_dir/release-candidate.yml"
promotion_workflow="$workflows_dir/promote-release.yml"
refresh_workflow="$workflows_dir/refresh-release-status.yml"

grep -Eq '^permissions:$' "$ci_workflow" \
  || fail "CI must declare workflow permissions"
grep -Eq '^  contents: read$' "$ci_workflow" \
  || fail "CI must be contents-read-only"
if grep -En 'secrets\.|gh release|git push|pages|homebrew' "$ci_workflow" >/dev/null; then
  fail "ordinary CI contains a publication capability"
fi
grep -Eq 'website-handoff-tests.sh' "$ci_workflow" \
  || fail "ordinary CI skips the website handoff contract"

grep -Eq 'tags:' "$candidate_workflow" \
  || fail "candidate workflow is not tag-triggered"
grep -Eq 'attest-build-provenance' "$candidate_workflow" \
  || fail "candidate workflow does not attest canonical bytes"
grep -Eq 'attestation.json' "$candidate_workflow" \
  || fail "candidate workflow does not attest its provenance receipt"
grep -Eq 'upload-artifact' "$candidate_workflow" \
  || fail "candidate workflow does not preserve the candidate"
if grep -En 'secrets\.|gh release|git push|release-production' \
  "$candidate_workflow" >/dev/null
then
  fail "tag candidate workflow can access publication capabilities"
fi
if grep -En 'sparkle-signature|KEEP3_.*PRIVATE|generate-channel-metadata' \
  "$candidate_workflow" >/dev/null
then
  fail "credential-free candidate workflow attempts to sign release metadata"
fi

grep -Eq 'schedule:' "$refresh_workflow" \
  || fail "release status freshness is not refreshed on a schedule"
grep -Eq '^  group: promote-release-channel$' "$refresh_workflow" \
  || fail "status refresh does not share the promotion lock"
grep -Eq 'environment: release-production' "$refresh_workflow" \
  || fail "status refresh is not protected by the release environment"
grep -Eq 'refresh-release-status.sh' "$refresh_workflow" \
  || fail "status refresh workflow does not use the trusted refresher"
grep -Fq -- '-v+90d' "$refresh_workflow" \
  || fail "status refresh does not renew the 90-day freshness window"

grep -Eq 'workflow_dispatch:' "$promotion_workflow" \
  || fail "promotion must require explicit dispatch"
grep -Eq '^  group: promote-release-channel$' "$promotion_workflow" \
  || fail "all tags must share one release-channel promotion lock"
grep -Eq '^  preflight:$' "$promotion_workflow" \
  || fail "promotion lacks a credential-free preflight job"
grep -Eq '^  promote:$' "$promotion_workflow" \
  || fail "promotion lacks a protected promotion job"
grep -Eq 'needs: preflight' "$promotion_workflow" \
  || fail "protected promotion does not depend on preflight"
grep -Eq 'environment: release-production' "$promotion_workflow" \
  || fail "promotion is not protected by the release environment"
grep -Eq 'ref: main' "$promotion_workflow" \
  || fail "promotion does not run trusted main tooling"
grep -Eq 'merge-base --is-ancestor' "$promotion_workflow" \
  || fail "promotion does not prove tag reachability from main"
grep -Eq 'gh attestation verify' "$promotion_workflow" \
  || fail "promotion does not verify candidate provenance"
for provenance_policy in \
  '--source-digest "$tag_commit"' \
  '--source-ref "refs/tags/$tag"' \
  '--signer-workflow "$signer_workflow"' \
  '--signer-digest "$tag_commit"' \
  '--deny-self-hosted-runners'
do
  grep -Fq -- "$provenance_policy" "$promotion_workflow" \
    || fail "promotion does not bind attestation policy: $provenance_policy"
done
grep -Eq 'gh run view.*candidate_run_id' "$promotion_workflow" \
  || fail "promotion does not verify the selected candidate workflow run"
grep -Eq 'run_head_sha=' "$promotion_workflow" && grep -Eq 'headSha' "$promotion_workflow" \
  || fail "promotion does not read the selected run head SHA"
grep -Eq 'test.*run_head_sha.*tag_commit' "$promotion_workflow" \
  || fail "promotion does not bind the selected run to the tag commit"
grep -Eq 'strict-monotonic' "$promotion_workflow" \
  || fail "promotion does not enforce strict build monotonicity"
grep -Eq '90 \* 24 \* 60 \* 60' "$promotion_workflow" \
  || fail "promotion reuses the 30-day candidate expiry as public freshness"
grep -Eq 'hdiutil attach' "$promotion_workflow" \
  || fail "promotion does not validate the app inside the attested DMG"
grep -Eq 'appcast.xml.*>/dev/null' "$promotion_workflow" \
  || fail "promotion does not sign the required Sparkle feed"
grep -Eq 'unexpected channel response' "$promotion_workflow" \
  || fail "promotion does not fail closed on channel read errors"
grep -Fq -- '--connect-timeout 10 --max-time 60' "$promotion_workflow" \
  || fail "promotion channel reads have no bounded timeout"
grep -Fq -- '--connect-timeout 10 --max-time 60' \
  "$release_scripts_dir/probe-channels.sh" \
  || fail "live channel probes have no bounded timeout"
for required_command in \
  generate-channel-metadata.sh \
  sign-release-metadata.sh \
  validate-release.sh \
  publish-release-channel.sh
do
  grep -Eq "$required_command" "$promotion_workflow" \
    || fail "protected promotion does not invoke $required_command"
done
grep -Eq '" gh-pages' "$release_scripts_dir/publish-release-channel.sh" \
  || fail "release channel publication does not target the Pages branch"
grep -Eq 'gh pr create' "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew promotion does not stage a candidate PR"
grep -Eq 'gh pr merge' "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew promotion does not merge the verified candidate PR"
if grep -Fq -- '--force-with-lease=' \
  "$release_scripts_dir/publish-release-channel.sh"
then
  fail "Homebrew promotion can rewrite a tap PR head after review"
fi
grep -Fq 'tap candidate branch exists without an open PR' \
  "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew promotion does not reject an unreviewed stale candidate branch"
grep -Fq 'expected_tap_head=$remote_branch_sha' \
  "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew promotion does not preserve the reviewed tap PR head"
grep -Eq -- '--match-head-commit' "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew merge is not pinned to the verified PR head"
grep -Eq 'headRefOid' "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew promotion does not inspect the remote PR head"
grep -Fq 'paths == ["Casks/keep3.rb"]' \
  "$release_scripts_dir/publish-release-channel.sh" \
  || fail "Homebrew promotion does not constrain the candidate file set"
if grep -Fq 'reviewDecision' \
  "$release_scripts_dir/publish-release-channel.sh"
then
  fail "single-maintainer Homebrew promotion still requires a second account approval"
fi
grep -Fq 'statusCheckRollup' \
  "$release_scripts_dir/publish-release-channel.sh" \
  || fail "single-maintainer Homebrew promotion does not require tap CI"
grep -Fq 'tap candidate PR was staged; inspect it and rerun promotion after CI passes' \
  "$release_scripts_dir/publish-release-channel.sh" \
  || fail "single-maintainer Homebrew promotion does not require a review-window rerun"
grep -Fq 'Single-maintainer tap approval' "$docs_dir/release-runbook.md" \
  || fail "release runbook does not document the single-maintainer tap gate"
if grep -En 'publish-release-channel\.sh --help|release-runbook\.md >/dev/null' \
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
printf 'next protected release\n' >> "$source_repository/README.md"
git -C "$source_repository" add README.md
git -C "$source_repository" commit -q -m 'Next protected release source'
git -C "$source_repository" tag v1.2.0
next_release_commit=$(git -C "$source_repository" rev-parse HEAD)

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
    "keyId" => key_id
  }
  status_common = common.merge("expiresAt" => "2030-04-01T00:00:00Z")
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
    status_sequence = {
      "Promoting" => 2, "Degraded" => 3, "Converged" => 4
    }.fetch(state)
    status = {
      "schemaVersion" => 1,
      "signed" => status_common.merge(
        "sequence" => status_sequence,
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
    "signed" => status_common.merge("sequence" => 3, "state" => "Compromised")
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
/usr/bin/ruby -rjson -e '
  paths = ARGV
  sequences = paths.map do |path|
    JSON.parse(File.read(path)).fetch("signed").fetch("sequence")
  end
  abort "operational status sequences are not strictly increasing" unless
    sequences.each_cons(2).all? { |left, right| left < right }
' "$candidate/release-status-promoting.json" \
  "$candidate/release-status-degraded.json" \
  "$candidate/release-status-converged.json" \
  || fail "operational status transitions reuse a replay sequence"
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
  url "https://github.com/taobaorun/keep3/releases/download/v#{version}/Keep3-#{version}.dmg"
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

/usr/bin/ruby -rjson -e '
  start = Integer(ARGV.shift)
  ARGV.each_with_index do |path, index|
    value = JSON.parse(File.read(path))
    value.fetch("signed")["sequence"] = start + index
    File.write(path, JSON.pretty_generate(value) + "\n")
  end
' 4 "$candidate/release-status-promoting.unsigned.json" \
  "$candidate/release-status-degraded.unsigned.json" \
  "$candidate/release-status-converged.unsigned.json"
for state in promoting degraded converged; do
  "$signer" sign \
    --input "$candidate/release-status-$state.unsigned.json" \
    --output "$candidate/release-status-$state.json" \
    --private-key "$private_key" --key-id "$key_id"
done

atomic_remote="$test_directory/atomic-remote"
atomic_state="$test_directory/atomic-state"
expect_rejected "injected failure before atomic convergence" run_publisher \
  "$candidate" "$atomic_remote" "$atomic_state" v1.0.0 \
  "$test_directory/previous-current.json" '' --fail-after current
test -f "$atomic_remote/github/releases/v1.0.0/stable" \
  || fail "atomic convergence test did not reach public promotion"
test -f "$atomic_remote/pages/release-channel/appcast.xml" \
  || fail "atomic convergence test did not reach the active appcast"
test ! -f "$atomic_remote/pages/release-channel/current-release.json" \
  || fail "current moved without its Converged status"
test "$(/usr/bin/ruby -rjson -e \
  'puts JSON.parse(File.read(ARGV[0])).dig("signed", "state")' \
  "$atomic_remote/pages/release-channel/release-status.json")" = Degraded \
  || fail "atomic convergence failure was not recorded as Degraded"

run_publisher "$candidate" "$remote" "$promotion_state" v1.0.0 \
  "$test_directory/previous-current.json" '' >/dev/null
"$release_scripts_dir/probe-channels.sh" \
  --mode fixture --tag v1.0.0 --version 1.0.0 --build 2 \
  --sha256 "$candidate_digest" --dmg-name Keep3-1.0.0.dmg \
  --manifest "$candidate/manifest.json" --appcast "$candidate/appcast.xml" \
  --cask "$candidate/keep3.rb" --channel-root "$remote" \
  --require-current >/dev/null

fresh_retry_state="$test_directory/fresh-retry-state"
run_publisher "$candidate" "$remote" "$fresh_retry_state" v1.0.0 \
  "$remote/pages/release-channel/current-release.json" \
  "$remote/pages/release-channel/release-status.json" >/dev/null \
  || fail "a converged candidate could not resume on a fresh runner"
test ! -e "$fresh_retry_state/events.log" \
  || fail "an already-converged retry repeated publication events"

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

next_candidate="$test_directory/next-candidate"
/usr/bin/ditto "$candidate" "$next_candidate"
mv "$next_candidate/Keep3-1.0.0.dmg" "$next_candidate/Keep3-1.2.0.dmg"
rm "$next_candidate/Keep3-1.0.0.dmg.sha256"
printf 'next release bytes\n' >> "$next_candidate/Keep3-1.2.0.dmg"
next_digest=$(shasum -a 256 "$next_candidate/Keep3-1.2.0.dmg" | awk '{print $1}')
next_size=$(stat -f '%z' "$next_candidate/Keep3-1.2.0.dmg")
printf '%s\n' "$next_digest" > "$next_candidate/Keep3-1.2.0.dmg.sha256"
/usr/bin/ruby -rjson -e '
  directory, digest, size, commit = ARGV
  artifact_url = "https://github.com/taobaorun/keep3/releases/download/v1.2.0/Keep3-1.2.0.dmg"
  manifest_url = "https://taobaorun.github.io/keep3/release-channel/releases/v1.2.0/manifest.json"
  old_manifest_url = "https://taobaorun.github.io/keep3/release-channel/releases/v1.0.0/manifest.json"
  manifest_path = File.join(directory, "manifest.unsigned.json")
  manifest = JSON.parse(File.read(manifest_path))
  release = manifest.fetch("signed")
  release.merge!("sequence" => 3, "version" => "1.2.0", "build" => 3,
    "tag" => "v1.2.0", "publishedAt" => "2030-01-02T00:00:00Z")
  release.fetch("artifact").merge!("fileName" => "Keep3-1.2.0.dmg",
    "url" => artifact_url, "sha256" => digest, "size" => Integer(size))
  release.fetch("source").merge!(
    "tagUrl" => "https://github.com/taobaorun/keep3/tree/v1.2.0",
    "archiveUrl" => "https://github.com/taobaorun/keep3/archive/refs/tags/v1.2.0.tar.gz",
    "commit" => commit)
  release.fetch("channels")["manifestUrl"] = manifest_url
  release.fetch("provenance").merge!("gitCommit" => commit,
    "candidateDigest" => digest)
  File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")

  current_path = File.join(directory, "current-release.unsigned.json")
  current = JSON.parse(File.read(current_path))
  stable = current.fetch("signed")
  stable.merge!("sequence" => 3, "version" => "1.2.0", "build" => 3,
    "tag" => "v1.2.0", "publishedAt" => "2030-01-02T00:00:00Z",
    "manifestUrl" => manifest_url, "artifactUrl" => artifact_url)
  File.write(current_path, JSON.pretty_generate(current) + "\n")

  { "promoting" => ["Promoting", 7, old_manifest_url],
    "degraded" => ["Degraded", 8, old_manifest_url],
    "converged" => ["Converged", 9, manifest_url] }.each do |name, values|
    path = File.join(directory, "release-status-#{name}.unsigned.json")
    status = JSON.parse(File.read(path))
    signed = status.fetch("signed")
    signed.merge!("sequence" => values[1], "version" => "1.2.0", "build" => 3,
      "tag" => "v1.2.0", "publishedAt" => "2030-01-02T00:00:00Z",
      "expiresAt" => "2030-04-02T00:00:00Z",
      "candidateManifestUrl" => manifest_url,
      "currentManifestUrl" => values[2], "state" => values[0])
    File.write(path, JSON.pretty_generate(status) + "\n")
  end

  appcast_path = File.join(directory, "appcast.xml")
  appcast = File.read(appcast_path).gsub("1.0.0", "1.2.0")
    .sub(%q[sparkle:version="2"], %q[sparkle:version="3"])
  File.write(appcast_path, appcast)
  cask_path = File.join(directory, "keep3.rb")
  cask = File.read(cask_path).gsub("1.0.0", "1.2.0")
    .sub(/sha256 "[0-9a-f]+"/, "sha256 \"#{digest}\"")
  File.write(cask_path, cask)
  receipt = { "repository" => "taobaorun/keep3", "tag" => "v1.2.0",
    "commit" => commit, "build" => 3, "sha256" => digest }
  File.write(File.join(directory, "attestation.json"),
    JSON.pretty_generate(receipt) + "\n")
' "$next_candidate" "$next_digest" "$next_size" "$next_release_commit"
for name in manifest current-release release-status-promoting \
  release-status-degraded release-status-converged
do
  "$signer" sign \
    --input "$next_candidate/$name.unsigned.json" \
    --output "$next_candidate/$name.json" \
    --private-key "$private_key" --key-id "$key_id"
done

next_state="$test_directory/next-promotion-state"
run_publisher "$next_candidate" "$remote" "$next_state" v1.2.0 \
  "$remote/pages/release-channel/current-release.json" \
  "$remote/pages/release-channel/release-status.json" >/dev/null
cmp -s "$next_candidate/appcast.xml" \
  "$remote/pages/release-channel/appcast.xml" \
  || fail "a later release could not replace the active appcast"
cmp -s "$next_candidate/keep3.rb" "$remote/tap/Casks/keep3.rb" \
  || fail "a later release could not replace the active cask"
"$release_scripts_dir/probe-channels.sh" \
  --mode fixture --tag v1.2.0 --version 1.2.0 --build 3 \
  --sha256 "$next_digest" --dmg-name Keep3-1.2.0.dmg \
  --manifest "$next_candidate/manifest.json" \
  --appcast "$next_candidate/appcast.xml" --cask "$next_candidate/keep3.rb" \
  --channel-root "$remote" --require-current >/dev/null

printf 'channel-promotion-tests: passed\n'
