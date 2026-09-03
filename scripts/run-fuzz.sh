#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository_tmp="$repository_root/target/tmp"
evidence_directory="$repository_root/target/verification"
evidence="$evidence_directory/fuzz.log"
fuzz_runs="${FUZZ_RUNS:-100000}"
mkdir -p "$repository_tmp" "$evidence_directory"
cd "$repository_root"

if [[ ! "$fuzz_runs" =~ ^[1-9][0-9]*$ ]]; then
  printf 'FUZZ_RUNS must be a positive decimal integer: %s\n' "$fuzz_runs" >&2
  exit 2
fi

if [[ "${LIBVGRAPH_INTEROP_FUZZ_SCOPED:-0}" != 1 ]]; then
  exec systemd-run --user --scope \
    -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% -p TasksMax=64 \
    env LIBVGRAPH_INTEROP_FUZZ_SCOPED=1 CARGO_BUILD_JOBS=1 \
    TMPDIR="$repository_tmp" FUZZ_RUNS="$fuzz_runs" \
    "$repository_root/scripts/run-fuzz.sh"
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  printf '%s\n' 'fuzz evidence requires a clean source commit' >&2
  exit 1
fi
if [[ "$(cargo fuzz --version)" != 'cargo-fuzz 0.13.1' ]]; then
  printf '%s\n' 'cargo-fuzz 0.13.1 is required' >&2
  exit 1
fi

source_commit="$(git rev-parse HEAD)"
mkdir -p "$repository_root/target/fuzz-runs"
run_directory="$(mktemp -d "$repository_root/target/fuzz-runs/$source_commit.XXXXXXXX")"
corpus="$run_directory/corpus"
artifacts="$run_directory/artifacts"
mkdir -p "$corpus" "$artifacts"

printf '%s' \
  '4c5647534e5000014c5647492d4353522d4657442d563121010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000' \
  | xxd -r -p > "$corpus/empty-v1"
cp "$repository_root/fuzz/corpus/decode/empty" "$corpus/truncated-magic"
cp "$repository_root/fuzz/corpus/decode/truncated-header" "$corpus/truncated-schema"

fuzz_lock="$repository_root/fuzz/Cargo.lock"
lock_digest_before="$(sha256sum "$fuzz_lock" | cut -d' ' -f1)"
{
  printf 'timestamp='; date --utc --iso-8601=seconds
  printf 'source_commit=%s\n' "$source_commit"
  printf 'fuzz_runs=%s\n' "$fuzz_runs"
  printf 'run_directory=%s\n' "$run_directory"
  printf 'fuzz_lock_sha256=%s\n' "$lock_digest_before"
  cargo fuzz --version
  rustc +nightly-2026-04-21 -Vv
  sha256sum "$corpus/empty-v1" "$corpus/truncated-magic" "$corpus/truncated-schema"
} > "$evidence"

cargo +nightly-2026-04-21 fetch --locked --manifest-path "$repository_root/fuzz/Cargo.toml" \
  >> "$evidence" 2>&1
CARGO_NET_OFFLINE=true cargo +nightly-2026-04-21 fuzz run decode "$corpus" -- \
  -runs="$fuzz_runs" -max_len=1048576 -timeout=10 \
  -artifact_prefix="$artifacts/" >> "$evidence" 2>&1

lock_digest_after="$(sha256sum "$fuzz_lock" | cut -d' ' -f1)"
if [[ "$lock_digest_after" != "$lock_digest_before" ]]; then
  printf '%s\n' 'fuzz execution changed fuzz/Cargo.lock' >&2
  exit 1
fi
if ! rg -q '#[0-9]+[[:space:]]+DONE' "$evidence"; then
  printf '%s\n' 'libFuzzer did not report a completed bounded campaign' >&2
  exit 1
fi
mapfile -t crash_artifacts < <(find "$artifacts" -type f -print)
if [[ "${#crash_artifacts[@]}" -ne 0 ]]; then
  printf 'fuzz campaign produced %s crash artifact(s)\n' \
    "${#crash_artifacts[@]}" >&2
  printf '%s\n' "${crash_artifacts[@]}" >&2
  exit 1
fi

printf 'fuzz campaign passed %s runs at %s\n' "$fuzz_runs" "$source_commit"
