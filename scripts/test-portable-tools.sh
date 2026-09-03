#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repository_root/scripts/check-portable-tools.sh"
test_root="$repository_root/target/portable-tool-tests"
mkdir -p "$test_root"
run_directory="$(mktemp -d "$test_root/run.XXXXXXXX")"
trap 'rm -rf -- "$run_directory"' EXIT

# shellcheck source=scripts/check-portable-tools.sh
source "$checker"

portable_tool_closure_is_explicit bash grep
if portable_tool_closure_is_explicit __libvgraph_missing_command__ \
    > "$run_directory/missing.log" 2>&1; then
  printf '%s\n' 'portable tool closure admitted a missing command' >&2
  exit 1
fi

"$checker" bootstrap > "$run_directory/bootstrap.log"
"$checker" complete > "$run_directory/complete.log"
if "$checker" unknown > "$run_directory/unknown.log" 2>&1; then
  printf '%s\n' 'portable tool closure admitted an unknown phase' >&2
  exit 1
fi

nonportable_tool='r''g'
if grep -R -E -n \
    "(^|[[:space:]])${nonportable_tool}([[:space:]]|$)" \
    "$repository_root/scripts" "$repository_root/.github/workflows" \
    > "$run_directory/nonportable.log"; then
  printf 'undeclared nonportable command remains:\n%s\n' \
    "$(<"$run_directory/nonportable.log")" >&2
  exit 1
fi

printf '%s\n' \
  'verified declared command closure, missing-command rejection, and no ripgrep dependency'
