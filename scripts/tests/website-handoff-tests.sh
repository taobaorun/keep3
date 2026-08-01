#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
handoff="$repository_root/docs/distribution/website-handoff.md"
distribution_verification="$repository_root/docs/verification/keep3-distribution.md"

fail() {
  printf 'website-handoff-tests: %s\n' "$1" >&2
  exit 1
}

require_file() {
  test -f "$1" || fail "missing required file: ${1#$repository_root/}"
}

require_text() {
  file=$1
  text=$2
  grep -Fq -- "$text" "$file" \
    || fail "${file#$repository_root/} is missing: $text"
}

reject_text() {
  file=$1
  text=$2
  if grep -Fq -- "$text" "$file"; then
    fail "${file#$repository_root/} contains obsolete text: $text"
  fi
}

require_file "$handoff"
require_file "$distribution_verification"
require_file "$repository_root/distribution/release-metadata-public-key.pem"

for contract_reference in \
  'distribution/current-release.schema.json' \
  'distribution/release-status.schema.json' \
  'distribution/release-manifest.schema.json' \
  'distribution/release-metadata-public-key.pem' \
  'https://taobaorun.github.io/keep3/release-channel/current-release.json' \
  'https://taobaorun.github.io/keep3/release-channel/release-status.json' \
  'https://taobaorun.github.io/keep3/release-channel/appcast.xml' \
  'taobaorun/keep3'
do
  require_text "$handoff" "$contract_reference"
done

require_text "$handoff" 'byte-identical cached envelope'
require_text "$handoff" 'Only `release-status.json` carries `expiresAt`'
require_text "$handoff" 'Refresh release status'
require_text "$handoff" '`keep3-release-metadata-production`'
reject_text "$handoff" 'checked-in key is a development fixture'
if grep -Fq -- 'Connect the protected U4 workflow' "$distribution_verification"; then
  fail 'readiness ledger incorrectly reports the protected publisher as unwired'
fi
require_text "$distribution_verification" 'Protected publisher live exercise'

for verification_rule in \
  'Ed25519' \
  'schemaVersion' \
  'canonicalOrigin' \
  'repository' \
  'signature' \
  'expiresAt' \
  'sequence' \
  'build' \
  'trustState' \
  'sha256' \
  'source tag' \
  'Homebrew'
do
  require_text "$handoff" "$verification_rule"
done

for website_rule in \
  'unique download clicks' \
  '90-day' \
  'tracking failure' \
  'never gates the download' \
  'donation failure' \
  'no app telemetry' \
  'privacy disclosure' \
  'unsigned' \
  'Developer ID'
do
  require_text "$handoff" "$website_rule"
done

for continuity_rule in \
  'dev.keep3.Keep3' \
  'com.apple.controlcenter.Keep3MediaService' \
  '~/Library/Application Support/Keep3/state.json' \
  'UserDefaults' \
  'SUPublicEDKey' \
  'CURRENT_PROJECT_VERSION' \
  'must never return to unsigned'
do
  require_text "$handoff" "$continuity_rule"
done

for blocker in \
  'GPL compatibility review' \
  'live media/provider checks' \
  'permanent Sparkle key' \
  'permanent metadata key' \
  'tap ownership' \
  'gh-pages' \
  'standalone website readiness' \
  'channel credentials'
do
  require_text "$distribution_verification" "$blocker"
done

require_text "$repository_root/README.md" 'docs/distribution/website-handoff.md'
require_text "$repository_root/README.md" 'docs/verification/keep3-distribution.md'
require_text "$repository_root/docs/verification/keep3-mvp.md" 'keep3-distribution.md'
require_text "$repository_root/docs/verification/keep3-media-compatibility.md" \
  'keep3-distribution.md'

printf 'website-handoff-tests: passed\n'
