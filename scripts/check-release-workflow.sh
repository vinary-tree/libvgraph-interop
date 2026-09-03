#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${LIBVGRAPH_RELEASE_WORKFLOW:-$repository_root/.github/workflows/release.yml}"

fail() {
  printf 'release workflow policy violation: %s\n' "$1" >&2
  exit 1
}

require_literal() {
  local literal="$1"
  if ! grep -F -q -- "$literal" "$workflow"; then
    fail "missing required text: $literal"
  fi
}

forbid_pattern() {
  local pattern="$1"
  if grep -E -q -- "$pattern" "$workflow"; then
    fail "forbidden pattern is present: $pattern"
  fi
}

step_line() {
  local name="$1"
  local count
  count="$(grep -F -c -- "- name: $name" "$workflow" || true)"
  if [[ "$count" -ne 1 ]]; then
    fail "expected exactly one step named '$name', found $count"
  fi
  grep -F -n -- "- name: $name" "$workflow" | cut -d: -f1
}

if [[ ! -f "$workflow" || -L "$workflow" ]]; then
  fail 'release.yml must be a regular file'
fi

require_literal 'workflow_dispatch:'
require_literal "group: release-\${{ inputs.tag }}"
require_literal 'cancel-in-progress: false'
require_literal 'environment: crates-io'
require_literal 'attestations: write'
require_literal 'contents: write'
require_literal 'id-token: write'
require_literal 'refs/heads/main'
require_literal 'scripts/validate-release-version.sh'
require_literal "verify-tag \"\$tag\""
require_literal 'scripts/verify-release-candidate.sh'
require_literal 'scripts/registry-release-status.sh'
require_literal 'scripts/build-release-evidence.sh'
require_literal 'scripts/reconcile-release-assets.sh'
require_literal "scripts/generate-release-sbom.sh \"\$VERSION\" target/release"
require_literal 'cargo publish --locked'
require_literal 'actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8'
require_literal 'actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6'
require_literal 'sbom-path:'
require_literal "inputs.registry_auth == 'trusted-publisher'"
require_literal "inputs.registry_auth == 'bootstrap-token'"
require_literal "version_without_build=\"\${version_without_build%%+*}\""
require_literal "repos/\${GITHUB_REPOSITORY}/immutable-releases"

forbid_pattern '^[[:space:]]+release:'
forbid_pattern '^[[:space:]]+push:'
forbid_pattern '^[[:space:]]+pull_request(_target)?:'
forbid_pattern '^[[:space:]]+workflow_run:'
forbid_pattern '--clobber'

mapfile -t unpinned_actions < <(
  awk '/^[[:space:]]+uses:/ {
    value = $2
    split(value, parts, "@")
    if (length(parts[2]) != 40 || parts[2] !~ /^[0-9a-f]+$/) print NR ":" value
  }' "$workflow"
)
if [[ "${#unpinned_actions[@]}" -ne 0 ]]; then
  printf '%s\n' "${unpinned_actions[@]}" >&2
  fail 'every action must be pinned to one full lowercase commit SHA'
fi

ordered_steps=(
  'Verify tag against protected signer policy'
  'Verify candidate is protected main'
  'Run complete release gates'
  'Reject incompatible release state'
  'Create draft release'
  'Verify crates.io checksum'
  'Attach complete immutable assets'
  'Publish immutable release'
)
previous_line=0
for required_step in "${ordered_steps[@]}"; do
  current_line="$(step_line "$required_step")"
  if [[ "$current_line" -le "$previous_line" ]]; then
    fail "step '$required_step' is out of order"
  fi
  previous_line="$current_line"
done

if [[ "$(grep -F -o -- 'cargo publish --locked' "$workflow" | wc -l)" -ne 1 ]]; then
  fail 'the crate publication command must occur exactly once'
fi
if [[ "$(grep -F -o -- '-F draft=false' "$workflow" | wc -l)" -ne 1 ]]; then
  fail 'the release publication mutation must occur exactly once'
fi

printf '%s\n' \
  'verified fail-closed release workflow trigger, trust, gate, registry, asset, and publication order'
