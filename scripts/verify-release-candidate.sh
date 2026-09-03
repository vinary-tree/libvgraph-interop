#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
evidence_directory="$repository_root/target/verification"
repository_tmp="$repository_root/target/tmp"
mkdir -p "$evidence_directory" "$repository_tmp"
cd "$repository_root"

if [[ "${LIBVGRAPH_INTEROP_RELEASE_SCOPED:-0}" != 1 ]]; then
  exec systemd-run --user --scope \
    -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% -p TasksMax=64 \
    env LIBVGRAPH_INTEROP_RELEASE_SCOPED=1 \
    LIBVGRAPH_INTEROP_FUZZ_SCOPED=1 \
    LIBVGRAPH_INTEROP_MUTATION_SCOPED=1 \
    LIBVGRAPH_INTEROP_BENCH_SCOPED=1 \
    LIBVGRAPH_INTEROP_DOCS_SCOPED=1 \
    CARGO_BUILD_JOBS=1 TMPDIR="$repository_tmp" \
    LIBVGRAPH_FORMAL_SOURCE="${LIBVGRAPH_FORMAL_SOURCE:-$repository_root/../libvgraph-vco-e2-interop-formal}" \
    "$repository_root/scripts/verify-release-candidate.sh"
fi

run_gate() {
  local name="$1"
  shift
  printf '==> %s\n' "$name"
  "$@" >"$evidence_directory/$name.log" 2>&1
}

run_gate release-portable "$repository_root/scripts/verify-portable.sh"
run_gate release-fuzz "$repository_root/scripts/run-fuzz.sh"
run_gate release-mutation "$repository_root/scripts/run-mutation.sh"
run_gate release-benchmark "$repository_root/scripts/run-benchmark.sh"

printf '%s\n' 'all commit-bound libvgraph-interop release-candidate gates passed'
