#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repository_root/.github/workflows/release.yml"
checker="$repository_root/scripts/check-release-workflow.sh"
test_root="$repository_root/target/release-workflow-tests"
mkdir -p "$test_root"
run_directory="$(mktemp -d "$test_root/run.XXXXXXXX")"
trap 'rm -rf -- "$run_directory"' EXIT

replace_literal() {
  local file="$1"
  local search="$2"
  local replacement="$3"
  if [[ "$(rg -F -c -- "$search" "$file")" -lt 1 ]]; then
    printf 'release workflow test cannot find mutation target: %s\n' "$search" >&2
    exit 1
  fi
  SEARCH="$search" REPLACEMENT="$replacement" perl -0pi -e \
    's/\Q$ENV{SEARCH}\E/$ENV{REPLACEMENT}/' "$file"
}

expect_rejected() {
  local label="$1"
  local search="$2"
  local replacement="$3"
  local mutant="$run_directory/$label.yml"
  cp "$workflow" "$mutant"
  replace_literal "$mutant" "$search" "$replacement"
  if LIBVGRAPH_RELEASE_WORKFLOW="$mutant" "$checker" \
      > "$run_directory/$label.log" 2>&1; then
    printf 'release workflow mutant unexpectedly passed: %s\n' "$label" >&2
    exit 1
  fi
}

LIBVGRAPH_RELEASE_WORKFLOW="$workflow" "$checker" \
  > "$run_directory/positive.log" 2>&1
expect_rejected protected-signer \
  "verify-tag \"\$tag\"" "verify-disabled \"\$tag\""
expect_rejected semantic-version \
  'scripts/validate-release-version.sh' 'scripts/skip-release-version-validation.sh'
expect_rejected protected-head \
  'Verify candidate is protected main' 'Verify candidate without protected main'
expect_rejected gates \
  'scripts/verify-release-candidate.sh' 'scripts/skip-release-candidate.sh'
expect_rejected assets \
  'scripts/reconcile-release-assets.sh' 'scripts/skip-release-assets.sh'
expect_rejected sbom-generator \
  'scripts/generate-release-sbom.sh' 'scripts/skip-release-sbom.sh'
expect_rejected sbom-directory \
  "\"\$VERSION\" target/release" "\"\$VERSION\" target/untrusted-release"
expect_rejected registry \
  'Verify crates.io checksum' 'Skip crates.io checksum'
expect_rejected republish \
  "-F draft=false -f make_latest=\"\$make_latest\"" \
  "-F draft=false -F draft=false -f make_latest=\"\$make_latest\""
expect_rejected untrusted-trigger 'workflow_dispatch:' 'release:'

order_mutant="$run_directory/draft-order.yml"
cp "$workflow" "$order_mutant"
replace_literal "$order_mutant" 'Create draft release' '__DRAFT_STEP__'
replace_literal "$order_mutant" 'Verify crates.io checksum' 'Create draft release'
replace_literal "$order_mutant" '__DRAFT_STEP__' 'Verify crates.io checksum'
if LIBVGRAPH_RELEASE_WORKFLOW="$order_mutant" "$checker" \
    > "$run_directory/draft-order.log" 2>&1; then
  printf '%s\n' 'release workflow draft-order mutant unexpectedly passed' >&2
  exit 1
fi

printf '%s\n' \
  'verified positive release workflow and eleven independently rejected causal mutants'
