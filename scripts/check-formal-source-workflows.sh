#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ci_workflow="${LIBVGRAPH_CI_WORKFLOW:-$repository_root/.github/workflows/ci.yml}"
release_workflow="${LIBVGRAPH_RELEASE_WORKFLOW:-$repository_root/.github/workflows/release.yml}"
checkout_action_sha=3d3c42e5aac5ba805825da76410c181273ba90b1

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

workflow_uses_supported_checkout() {
  local workflow="$1"
  local checkout_ref
  local checkout_count=0
  while IFS= read -r checkout_ref; do
    checkout_count="$((checkout_count + 1))"
    if [[ "$checkout_ref" != "$checkout_action_sha" ]]; then
      printf 'workflow uses unsupported actions/checkout commit %s: %s\n' \
        "$checkout_ref" "$workflow" >&2
      return 1
    fi
  done < <(
    awk '/^[[:space:]]+uses: actions\/checkout@/ {
      split($2, parts, "@"); print parts[2]
    }' "$workflow"
  )
  if [[ "$checkout_count" -eq 0 ]]; then
    printf 'workflow has no immutable actions/checkout step: %s\n' "$workflow" >&2
    return 1
  fi
}

workflow_uses_canonical_formal_binding "$ci_workflow"
workflow_uses_canonical_formal_binding "$release_workflow"
workflow_uses_supported_checkout "$ci_workflow"
workflow_uses_supported_checkout "$release_workflow"
printf '%s\n' \
  'verified CI and release workflows consume one canonical formal-source binding and supported checkout action'
