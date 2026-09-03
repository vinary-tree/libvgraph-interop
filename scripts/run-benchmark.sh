#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository_tmp="$repository_root/target/tmp"
evidence="$repository_root/target/verification/benchmark.log"
mkdir -p "$repository_tmp" "$(dirname "$evidence")"
cd "$repository_root"

if [[ "${LIBVGRAPH_INTEROP_BENCH_SCOPED:-0}" != 1 ]]; then
  exec systemd-run --user --scope \
    -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% -p TasksMax=64 \
    env LIBVGRAPH_INTEROP_BENCH_SCOPED=1 CARGO_BUILD_JOBS=1 \
    TMPDIR="$repository_tmp" \
    "$repository_root/scripts/run-benchmark.sh"
fi

if [[ -n "$(git -C "$repository_root" status --porcelain)" ]]; then
  printf '%s\n' 'benchmark evidence requires a clean source commit' >&2
  exit 1
fi

{
  date --utc --iso-8601=seconds
  git -C "$repository_root" rev-parse HEAD
  rustc -Vv
  cargo -V
  lscpu
  rg '^(Cpus_allowed_list|Mems_allowed_list):' /proc/self/status
  if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
    sed -n '1p' /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
  else
    printf '%s\n' 'scaling governor unavailable'
  fi
  cargo bench --locked --bench codec -- --quick
} >"$evidence" 2>&1

for benchmark in \
  canonical_snapshot/encode/1000 \
  canonical_snapshot/decode/1000 \
  canonical_snapshot/encode/100000 \
  canonical_snapshot/decode/100000; do
  if ! rg -F -q -- "$benchmark" "$evidence"; then
    printf 'benchmark evidence omits workload: %s\n' "$benchmark" >&2
    exit 1
  fi
done
if [[ "$(rg -c 'time:' "$evidence")" -lt 4 ]]; then
  printf '%s\n' 'benchmark evidence omits one or more Criterion estimates' >&2
  exit 1
fi
printf 'benchmark campaign recorded four workloads at %s\n' \
  "$(git -C "$repository_root" rev-parse HEAD)"
