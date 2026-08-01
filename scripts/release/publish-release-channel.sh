#!/bin/sh
set -eu

fail() {
  printf 'publish-release-channel: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: publish-release-channel.sh --mode fixture|live --repository-root DIR
  [--source-repository DIR] --protected-ref REF --tag vX.Y.Z
  --candidate-dir DIR --attestation JSON
  --metadata-public-key PEM --metadata-key-id ID --state-dir DIR
  [--previous-current JSON] [--operational-status JSON]
  [--channel-root DIR] [--pages-worktree DIR] [--tap-worktree DIR]
  [--tap-cask-url URL] [--fail-after github|tap|appcast|probe|current]
  [--preflight-only]

The candidate directory must contain one Keep3-X.Y.Z.dmg and its .sha256
sidecar, manifest.json, appcast.xml, keep3.rb, current-release.json, and signed
release-status-{promoting,degraded,converged}.json documents.
USAGE
  exit 64
}

mode=''; repository_root=''; protected_ref=''; tag=''; candidate_dir=''
attestation=''; metadata_public_key=''; metadata_key_id=''; state_dir=''
previous_current=''; operational_status=''; channel_root=''; pages_worktree=''
tap_worktree=''; tap_cask_url=''; fail_after=''; preflight_only=false
source_repository=''
repository='taobaorun/keep3'
tap_repository='taobaorun/homebrew-keep3'
canonical_origin='https://taobaorun.github.io/keep3/release-channel'

while test "$#" -gt 0; do
  case "$1" in
    --mode) mode=${2-}; shift 2 ;;
    --repository-root) repository_root=${2-}; shift 2 ;;
    --source-repository) source_repository=${2-}; shift 2 ;;
    --protected-ref) protected_ref=${2-}; shift 2 ;;
    --tag) tag=${2-}; shift 2 ;;
    --candidate-dir) candidate_dir=${2-}; shift 2 ;;
    --attestation) attestation=${2-}; shift 2 ;;
    --metadata-public-key) metadata_public_key=${2-}; shift 2 ;;
    --metadata-key-id) metadata_key_id=${2-}; shift 2 ;;
    --state-dir) state_dir=${2-}; shift 2 ;;
    --previous-current) previous_current=${2-}; shift 2 ;;
    --operational-status) operational_status=${2-}; shift 2 ;;
    --channel-root) channel_root=${2-}; shift 2 ;;
    --pages-worktree) pages_worktree=${2-}; shift 2 ;;
    --tap-worktree) tap_worktree=${2-}; shift 2 ;;
    --tap-cask-url) tap_cask_url=${2-}; shift 2 ;;
    --fail-after) fail_after=${2-}; shift 2 ;;
    --preflight-only) preflight_only=true; shift ;;
    --help|-h) usage ;;
    *) usage ;;
  esac
done

case "$mode" in fixture|live) ;; *) usage ;; esac
test -d "$repository_root/.git" || fail "repository root is not a Git checkout"
test -n "$source_repository" || source_repository=$repository_root
test -d "$source_repository/.git" || fail "source repository is not a Git checkout"
test -n "$protected_ref" || fail "protected ref is required"
test -d "$candidate_dir" || fail "candidate directory is missing"
test -f "$attestation" || fail "candidate attestation is missing"
test -f "$metadata_public_key" || fail "metadata public key is missing"
test -n "$metadata_key_id" || fail "metadata key identifier is required"
test -n "$state_dir" || fail "state directory is required"
case "$fail_after" in ''|github|tap|appcast|probe|current) ;; *) usage ;; esac
if test "$mode" = fixture; then
  test -n "$channel_root" || fail "fixture mode requires --channel-root"
else
  test -d "$pages_worktree/.git" || fail "live mode requires a Pages worktree"
  test -d "$tap_worktree/.git" || fail "live mode requires a tap worktree"
  test -n "$tap_cask_url" || fail "live mode requires --tap-cask-url"
  test -n "${TAP_TOKEN-}" || fail "live mode requires TAP_TOKEN"
  command -v gh >/dev/null 2>&1 || fail "live mode requires gh"
fi

manifest="$candidate_dir/manifest.json"
appcast="$candidate_dir/appcast.xml"
cask="$candidate_dir/keep3.rb"
current="$candidate_dir/current-release.json"
promoting_status="$candidate_dir/release-status-promoting.json"
degraded_status="$candidate_dir/release-status-degraded.json"
converged_status="$candidate_dir/release-status-converged.json"
for required_file in "$manifest" "$appcast" "$cask" "$current" \
  "$promoting_status" "$degraded_status" "$converged_status"; do
  test -f "$required_file" || fail "candidate input is missing: $(basename -- "$required_file")"
done

if test "$mode" = live; then
  authoritative_current="$pages_worktree/release-channel/current-release.json"
  authoritative_status="$pages_worktree/release-channel/release-status.json"
  if test -f "$authoritative_current"; then
    previous_current=$authoritative_current
  fi
  if test -f "$authoritative_status"; then
    operational_status=$authoritative_status
  fi
fi

dmg=''; dmg_count=0
for candidate_dmg in "$candidate_dir"/Keep3-*.dmg; do
  if test -f "$candidate_dmg"; then
    dmg=$candidate_dmg
    dmg_count=$((dmg_count + 1))
  fi
done
test "$dmg_count" -eq 1 || fail "candidate must contain exactly one DMG"
digest_file="$dmg.sha256"
test -f "$digest_file" || fail "candidate digest sidecar is missing"
expected_digest=$(tr -d '[:space:]' < "$digest_file")
actual_digest=$(shasum -a 256 "$dmg" | awk '{print $1}')
test "$actual_digest" = "$expected_digest" \
  || fail "candidate digest does not match canonical bytes"

signer="$repository_root/scripts/release/sign-release-metadata.sh"
test -x "$signer" || fail "trusted metadata verifier is unavailable"
for signed_document in "$manifest" "$current" "$promoting_status" \
  "$degraded_status" "$converged_status"; do
  "$signer" verify --input "$signed_document" \
    --public-key "$metadata_public_key" \
    --expected-key-id "$metadata_key_id" >/dev/null \
    || fail "metadata signature is invalid: $(basename -- "$signed_document")"
done
if test -n "$previous_current"; then
  test -f "$previous_current" || fail "previous current document is missing"
  "$signer" verify --input "$previous_current" \
    --public-key "$metadata_public_key" \
    --expected-key-id "$metadata_key_id" >/dev/null \
    || fail "previous current signature is invalid"
fi

tag_commit=$(git -C "$source_repository" rev-parse "refs/tags/$tag^{commit}" 2>/dev/null) \
  || fail "release tag does not exist"
protected_commit=$(git -C "$source_repository" rev-parse "$protected_ref^{commit}" 2>/dev/null) \
  || fail "protected ref does not exist"
git -C "$source_repository" merge-base --is-ancestor "$tag_commit" "$protected_commit" \
  || fail "release tag is not reachable from the protected ref"

metadata_values=$(/usr/bin/ruby -rjson -e '
  manifest, current, promoting, degraded, converged, attestation,
    expected_tag, expected_commit, expected_digest, previous = ARGV
  release = JSON.parse(File.read(manifest)).fetch("signed")
  artifact = release.fetch("artifact")
  version = release.fetch("version")
  build = release.fetch("build")
  sequence = release.fetch("sequence")
  abort "manifest tag mismatch" unless release["tag"] == expected_tag && expected_tag == "v#{version}"
  abort "manifest commit mismatch" unless release.dig("source", "commit") == expected_commit
  abort "manifest digest mismatch" unless artifact["sha256"] == expected_digest
  abort "manifest candidate digest mismatch" unless release.dig("provenance", "candidateDigest") == expected_digest
  receipt = JSON.parse(File.read(attestation))
  abort "attestation repository mismatch" unless receipt["repository"] == "taobaorun/keep3"
  abort "attestation tag mismatch" unless receipt["tag"] == expected_tag
  abort "attestation commit mismatch" unless receipt["commit"] == expected_commit
  abort "attestation digest mismatch" unless receipt["sha256"] == expected_digest
  abort "attestation build mismatch" unless receipt["build"] == build
  current_release = JSON.parse(File.read(current)).fetch("signed")
  abort "current moved before convergence" unless current_release["state"] == "Converged"
  abort "current candidate mismatch" unless current_release["tag"] == expected_tag && current_release["build"] == build
  already_current = false
  status_sequences = []
  {
    promoting => "Promoting", degraded => "Degraded", converged => "Converged"
  }.each do |path, state|
    status = JSON.parse(File.read(path)).fetch("signed")
    abort "status state mismatch" unless status["state"] == state
    abort "status candidate mismatch" unless status["tag"] == expected_tag && status["build"] == build
    status_sequence = status.fetch("sequence")
    abort "status sequence must be positive" unless
      status_sequence.is_a?(Integer) && status_sequence.positive?
    status_sequences << status_sequence
  end
  abort "status sequences are not strict-monotonic" unless
    status_sequences.each_cons(2).all? { |left, right| left < right }
  unless previous.empty?
    old = JSON.parse(File.read(previous)).fetch("signed")
    if build > old.fetch("build")
      abort "candidate sequence is not strict-monotonic" unless sequence > old.fetch("sequence")
    elsif build == old.fetch("build")
      expected_manifest = release.dig("channels", "manifestUrl")
      expected_artifact = artifact.fetch("url")
      abort "equal build identifies a different release" unless
        old["state"] == "Converged" && old["tag"] == expected_tag &&
          old["version"] == version && old["manifestUrl"] == expected_manifest &&
          old["artifactUrl"] == expected_artifact
      already_current = true
    else
      abort "candidate build is not strict-monotonic"
    end
  end
  puts version, build, sequence, status_sequences.fetch(0), already_current
' "$manifest" "$current" "$promoting_status" "$degraded_status" \
  "$converged_status" "$attestation" "$tag" "$tag_commit" \
  "$actual_digest" "$previous_current") \
  || fail "candidate provenance or strict-monotonic validation failed"
version=$(printf '%s\n' "$metadata_values" | sed -n '1p')
build=$(printf '%s\n' "$metadata_values" | sed -n '2p')
sequence=$(printf '%s\n' "$metadata_values" | sed -n '3p')
promoting_status_sequence=$(printf '%s\n' "$metadata_values" | sed -n '4p')
already_current=$(printf '%s\n' "$metadata_values" | sed -n '5p')
test "$(basename -- "$dmg")" = "Keep3-$version.dmg" \
  || fail "candidate filename and version disagree"

journal_converged=false
if test -f "$state_dir/steps/converged"; then
  test -f "$state_dir/candidate.sha256" \
    || fail "converged promotion journal is missing its candidate digest"
  test "$(tr -d '[:space:]' < "$state_dir/candidate.sha256")" = "$actual_digest" \
    || fail "converged promotion journal belongs to different candidate bytes"
  journal_converged=true
fi

if test -z "$operational_status"; then
  if test "$mode" = fixture; then
    candidate_status="$channel_root/pages/release-channel/release-status.json"
  else
    candidate_status="$pages_worktree/release-channel/release-status.json"
  fi
  test ! -f "$candidate_status" || operational_status=$candidate_status
fi
if test -n "$operational_status" && test -f "$operational_status"; then
  "$signer" verify --input "$operational_status" \
    --public-key "$metadata_public_key" \
    --expected-key-id "$metadata_key_id" >/dev/null \
    || fail "operational status signature is invalid"
  operational_values=$(/usr/bin/ruby -rjson -rtime -e '
    signed = JSON.parse(File.read(ARGV.fetch(0))).fetch("signed")
    abort "unexpected status repository" unless signed["repository"] == "taobaorun/keep3"
    abort "unexpected status origin" unless signed["canonicalOrigin"] == "https://taobaorun.github.io"
    abort "operational status expired" unless Time.now.utc < Time.iso8601(signed.fetch("expiresAt"))
    puts signed.fetch("state"), signed.fetch("sequence")
  ' "$operational_status")
  operational_state=$(printf '%s\n' "$operational_values" | sed -n '1p')
  operational_sequence=$(printf '%s\n' "$operational_values" | sed -n '2p')
  test "$operational_state" != 'Compromised' \
    || fail "Compromised state freezes every publication channel"
  if test "$already_current" != true && test "$journal_converged" != true; then
    test "$promoting_status_sequence" -gt "$operational_sequence" \
      || fail "operational status sequence is not strict-monotonic"
  fi
fi

if $preflight_only; then
  printf 'publish-release-channel: preflight passed\n'
  exit 0
fi

mkdir -p "$state_dir/steps"
journal_digest="$state_dir/candidate.sha256"
if test -f "$journal_digest"; then
  test "$(tr -d '[:space:]' < "$journal_digest")" = "$actual_digest" \
    || fail "promotion journal belongs to different candidate bytes"
else
  printf '%s\n' "$actual_digest" > "$journal_digest"
fi
event_log="$state_dir/events.log"

record_step() {
  step=$1
  marker="$state_dir/steps/$step"
  if test ! -f "$marker"; then
    printf '%s\n' "$step" >> "$event_log"
    : > "$marker"
  fi
}

copy_immutable() {
  source_file=$1
  destination_file=$2
  mkdir -p "$(dirname -- "$destination_file")"
  if test -f "$destination_file"; then
    cmp -s "$source_file" "$destination_file" \
      || fail "refusing to replace immutable published bytes: $destination_file"
  else
    cp "$source_file" "$destination_file"
  fi
}

git_publish_path() {
  worktree=$1
  relative_path=$2
  message=$3
  branch=$4
  git -C "$worktree" add -- "$relative_path"
  if ! git -C "$worktree" diff --cached --quiet; then
    git -C "$worktree" commit -m "$message" >/dev/null
    git -C "$worktree" push origin "HEAD:$branch" >/dev/null
  fi
}

publish_status() {
  status_file=$1
  state_name=$2
  if test "$mode" = fixture; then
    destination="$channel_root/pages/release-channel/release-status.json"
    mkdir -p "$(dirname -- "$destination")"
    cp "$status_file" "$destination"
  else
    destination="$pages_worktree/release-channel/release-status.json"
    mkdir -p "$(dirname -- "$destination")"
    cp "$status_file" "$destination"
    git_publish_path "$pages_worktree" release-channel/release-status.json \
      "Record Keep3 release state: $state_name" gh-pages
  fi
  printf 'status:%s\n' "$state_name" >> "$event_log"
}

stage_tap_candidate() {
  if test "$mode" = fixture; then
    copy_immutable "$cask" "$channel_root/tap/candidates/$tag/keep3.rb"
    return
  fi

  ruby -c "$cask" >/dev/null || fail "candidate cask is invalid Ruby"
  git -C "$tap_worktree" fetch origin main >/dev/null
  published_cask="$state_dir/tap-published.rb"
  if git -C "$tap_worktree" show origin/main:Casks/keep3.rb \
    > "$published_cask" 2>/dev/null && cmp -s "$cask" "$published_cask"; then
    : > "$state_dir/tap-already-current"
    return
  fi

  tap_branch="release/keep3-$tag"
  remote_branch_sha=$(git -C "$tap_worktree" ls-remote --heads origin \
    "refs/heads/$tap_branch" | awk 'NR == 1 { print $1 }')
  git -C "$tap_worktree" switch -C "$tap_branch" origin/main >/dev/null
  destination="$tap_worktree/Casks/keep3.rb"
  mkdir -p "$(dirname -- "$destination")"
  cp "$cask" "$destination"
  git -C "$tap_worktree" add -- Casks/keep3.rb
  if ! git -C "$tap_worktree" diff --cached --quiet; then
    git -C "$tap_worktree" commit -m "Stage Keep3 $version" >/dev/null
  fi
  changed_paths=$(git -C "$tap_worktree" diff --name-only origin/main...HEAD)
  test "$changed_paths" = 'Casks/keep3.rb' \
    || fail "tap candidate contains changes outside Casks/keep3.rb"
  expected_tap_head=$(git -C "$tap_worktree" rev-parse HEAD)
  if test -n "$remote_branch_sha"; then
    git -C "$tap_worktree" push origin \
      --force-with-lease="refs/heads/$tap_branch:$remote_branch_sha" \
      "HEAD:refs/heads/$tap_branch" >/dev/null
  else
    git -C "$tap_worktree" push origin \
      "HEAD:refs/heads/$tap_branch" >/dev/null
  fi

  tap_pr=$(GH_TOKEN=$TAP_TOKEN gh pr list --repo "$tap_repository" \
    --head "$tap_branch" --state open --json number --jq '.[0].number')
  if test -z "$tap_pr"; then
    GH_TOKEN=$TAP_TOKEN gh pr create --repo "$tap_repository" \
      --base main --head "$tap_branch" \
      --title "Promote Keep3 $version" \
      --body "Promotes the verified canonical Keep3 $version DMG." >/dev/null
    tap_pr=$(GH_TOKEN=$TAP_TOKEN gh pr list --repo "$tap_repository" \
      --head "$tap_branch" --state open --json number --jq '.[0].number')
  fi
  test -n "$tap_pr" || fail "could not stage the tap candidate PR"
  printf '%s\n' "$tap_pr" > "$state_dir/tap-pr-number"
  printf '%s\n' "$expected_tap_head" > "$state_dir/tap-head-sha"
}

stage_draft() {
  if test "$mode" = fixture; then
    draft="$channel_root/github/drafts/$tag"
    copy_immutable "$dmg" "$draft/$(basename -- "$dmg")"
    copy_immutable "$manifest" "$draft/manifest.json"
    copy_immutable "$attestation" "$draft/attestation.json"
    copy_immutable "$digest_file" "$draft/$(basename -- "$digest_file")"
    return
  fi
  if ! gh release view "$tag" --repo "$repository" >/dev/null 2>&1; then
    gh release create "$tag" --repo "$repository" --draft --verify-tag \
      --title "Keep3 $version" --notes "Staged canonical Keep3 candidate."
  fi
  staging=$(mktemp -d /tmp/keep3-release-draft-XXXXXX)
  for asset in "$dmg" "$manifest" "$attestation" "$digest_file"; do
    name=$(basename -- "$asset")
    if gh release download "$tag" --repo "$repository" \
      --pattern "$name" --dir "$staging" >/dev/null 2>&1; then
      cmp -s "$asset" "$staging/$name" \
        || fail "draft release already contains different bytes: $name"
    else
      gh release upload "$tag" "$asset" --repo "$repository"
    fi
  done
}

publish_github() {
  if test "$mode" = fixture; then
    draft="$channel_root/github/drafts/$tag"
    release="$channel_root/github/releases/$tag"
    copy_immutable "$draft/$(basename -- "$dmg")" "$release/$(basename -- "$dmg")"
    copy_immutable "$draft/manifest.json" "$release/manifest.json"
    : > "$release/stable"
  else
    is_draft=$(gh release view "$tag" --repo "$repository" \
      --json isDraft --jq .isDraft)
    if test "$is_draft" = true; then
      gh release edit "$tag" --repo "$repository" --draft=false
    fi
  fi
  record_step github
}

publish_tap() {
  if test "$mode" = fixture; then
    destination="$channel_root/tap/Casks/keep3.rb"
    mkdir -p "$(dirname -- "$destination")"
    cp "$channel_root/tap/candidates/$tag/keep3.rb" "$destination"
  else
    if test ! -f "$state_dir/tap-already-current"; then
      test -f "$state_dir/tap-pr-number" \
        || fail "tap candidate PR was not staged"
      test -f "$state_dir/tap-head-sha" \
        || fail "tap candidate head SHA was not recorded"
      tap_pr=$(tr -d '[:space:]' < "$state_dir/tap-pr-number")
      expected_tap_head=$(tr -d '[:space:]' < "$state_dir/tap-head-sha")
      tap_pr_metadata=$(GH_TOKEN=$TAP_TOKEN gh pr view "$tap_pr" \
        --repo "$tap_repository" \
        --json baseRefName,files,headRefName,headRefOid,isCrossRepository,mergeable,reviewDecision,state,statusCheckRollup)
      printf '%s' "$tap_pr_metadata" | /usr/bin/ruby -rjson -e '
        expected_branch, expected_head = ARGV
        value = JSON.parse(STDIN.read)
        abort "tap PR is not open" unless value["state"] == "OPEN"
        abort "tap PR base mismatch" unless value["baseRefName"] == "main"
        abort "tap PR head branch mismatch" unless value["headRefName"] == expected_branch
        abort "tap PR head changed" unless value["headRefOid"] == expected_head
        abort "tap PR must originate in the tap repository" if value["isCrossRepository"]
        paths = value.fetch("files").map { |file| file.fetch("path") }
        abort "tap PR contains unexpected files" unless paths == ["Casks/keep3.rb"]
        abort "tap PR is not mergeable" unless value["mergeable"] == "MERGEABLE"
        abort "tap PR is not approved" unless value["reviewDecision"] == "APPROVED"
        checks = value.fetch("statusCheckRollup")
        abort "tap PR has no required checks" if checks.empty?
        accepted = %w[SUCCESS NEUTRAL SKIPPED]
        abort "tap PR checks are incomplete" unless checks.all? do |check|
          accepted.include?(check["conclusion"] || check["state"])
        end
      ' "$tap_branch" "$expected_tap_head" \
        || fail "tap candidate PR changed or is not approved"
      GH_TOKEN=$TAP_TOKEN gh pr merge "$tap_pr" --repo "$tap_repository" \
        --squash --delete-branch \
        --match-head-commit "$expected_tap_head" >/dev/null
    fi
    git -C "$tap_worktree" fetch origin main >/dev/null
    git -C "$tap_worktree" show origin/main:Casks/keep3.rb \
      > "$state_dir/tap-current.rb"
    cmp -s "$cask" "$state_dir/tap-current.rb" \
      || fail "merged tap cask does not match the candidate"
  fi
  record_step tap
}

publish_appcast() {
  if test "$mode" = fixture; then
    copy_immutable "$manifest" \
      "$channel_root/pages/release-channel/releases/$tag/manifest.json"
    cp "$appcast" "$channel_root/pages/release-channel/appcast.xml"
  else
    manifest_destination="$pages_worktree/release-channel/releases/$tag/manifest.json"
    appcast_destination="$pages_worktree/release-channel/appcast.xml"
    mkdir -p "$(dirname -- "$manifest_destination")"
    copy_immutable "$manifest" "$manifest_destination"
    cp "$appcast" "$appcast_destination"
    git_publish_path "$pages_worktree" release-channel \
      "Activate Keep3 $version appcast" gh-pages
  fi
  record_step appcast
}

publish_convergence() {
  test "$fail_after" != current \
    || fail "injected failure before atomic convergence publication"
  if test "$mode" = fixture; then
    release_channel="$channel_root/pages/release-channel"
    mkdir -p "$release_channel"
    cp "$current" "$release_channel/current-release.json"
    cp "$converged_status" "$release_channel/release-status.json"
  else
    release_channel="$pages_worktree/release-channel"
    mkdir -p "$release_channel"
    cp "$current" "$release_channel/current-release.json"
    cp "$converged_status" "$release_channel/release-status.json"
    git_publish_path "$pages_worktree" release-channel \
      "Converge Keep3 $version release discovery" gh-pages
  fi
  record_step current
  printf 'status:Converged\n' >> "$event_log"
}

run_probe() {
  require_current=${1-false}
  set -- "$repository_root/scripts/release/probe-channels.sh" \
    --mode "$mode" --tag "$tag" --version "$version" --build "$build" \
    --sha256 "$actual_digest" --dmg-name "$(basename -- "$dmg")" \
    --manifest "$manifest" --appcast "$appcast" --cask "$cask"
  if test "$mode" = fixture; then
    set -- "$@" --channel-root "$channel_root"
  else
    set -- "$@" \
      --repository "$repository" --canonical-origin "$canonical_origin" \
      --tap-cask-url "$tap_cask_url"
  fi
  if test "$require_current" = true; then
    set -- "$@" --require-current
  fi
  "$@" >/dev/null
}

if test "$already_current" = true; then
  run_probe true
  printf 'publish-release-channel: already converged %s build %s\n' \
    "$version" "$build"
  exit 0
fi

if test -f "$state_dir/steps/converged"; then
  run_probe true
  printf 'publish-release-channel: already converged %s build %s\n' \
    "$version" "$build"
  exit 0
fi

public_started=false
completed=false
recover_public_failure() {
  if test "$mode" = fixture; then
    publish_status "$degraded_status" Degraded >/dev/null 2>&1 || :
    return
  fi

  git -C "$pages_worktree" fetch origin gh-pages >/dev/null 2>&1 || return
  git -C "$pages_worktree" reset --hard origin/gh-pages >/dev/null 2>&1 || return
  remote_current="$pages_worktree/release-channel/current-release.json"
  remote_status="$pages_worktree/release-channel/release-status.json"
  if test -f "$remote_current" && test -f "$remote_status" \
    && cmp -s "$current" "$remote_current" \
    && cmp -s "$converged_status" "$remote_status"
  then
    completed=true
    return
  fi
  publish_status "$degraded_status" Degraded >/dev/null 2>&1 || :
}

on_exit() {
  result=$?
  trap - EXIT
  if test "$result" -ne 0 && $public_started && ! $completed; then
    recover_public_failure
  fi
  exit "$result"
}
trap 'on_exit' EXIT

stage_draft
stage_tap_candidate
record_step draft
if test -f "$state_dir/steps/github"; then public_started=true; fi
public_started=true
publish_github
publish_status "$promoting_status" Promoting
test "$fail_after" != github || fail "injected failure after GitHub publication"

publish_tap
test "$fail_after" != tap || fail "injected failure after tap publication"

publish_appcast
test "$fail_after" != appcast || fail "injected failure after appcast publication"

run_probe false
record_step probe
test "$fail_after" != probe || fail "injected failure after convergence probe"

publish_convergence
record_step converged
completed=true

printf 'publish-release-channel: converged %s build %s sequence %s\n' \
  "$version" "$build" "$sequence"
