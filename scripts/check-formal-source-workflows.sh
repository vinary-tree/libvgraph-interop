#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ci_workflow="${LIBVGRAPH_CI_WORKFLOW:-$repository_root/.github/workflows/ci.yml}"
release_workflow="${LIBVGRAPH_RELEASE_WORKFLOW:-$repository_root/.github/workflows/release.yml}"

workflow_uses_canonical_formal_binding() {
  local workflow="$1"
  local resolver_count
  local ref_count
  if [[ ! -f "$workflow" || -L "$workflow" ]]; then
    printf 'formal-source workflow must be a regular file: %s\n' "$workflow" >&2
    return 1
  fi
  resolver_count="$(grep -F -c -- 'scripts/resolve-formal-commit.sh' "$workflow" || true)"
  ref_count="$(grep -F -c -- "ref: \${{ steps.formal_source.outputs.commit }}" \
    "$workflow" || true)"
  if [[ "$resolver_count" -ne 1 || "$ref_count" -ne 1 ]]; then
    printf 'workflow must resolve and consume exactly one canonical formal binding: %s\n' \
      "$workflow" >&2
    return 1
  fi
  if grep -E -q '^[[:space:]]+ref: [0-9a-f]{40}[[:space:]]*$' "$workflow"; then
    printf 'workflow embeds a direct formal commit instead of the canonical binding: %s\n' \
      "$workflow" >&2
    return 1
  fi
}

workflow_uses_canonical_formal_binding "$ci_workflow"
workflow_uses_canonical_formal_binding "$release_workflow"
printf '%s\n' 'verified CI and release workflows consume one canonical formal-source binding'
