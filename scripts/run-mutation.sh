#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository_tmp="$repository_root/target/tmp"
evidence_directory="$repository_root/target/verification"
evidence="$evidence_directory/mutation.log"
metadata="$evidence_directory/mutation-metadata.log"
mkdir -p "$repository_tmp" "$evidence_directory"
cd "$repository_root"

if [[ "${LIBVGRAPH_INTEROP_MUTATION_SCOPED:-0}" != 1 ]]; then
  exec systemd-run --user --scope \
    -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% -p TasksMax=64 \
    env LIBVGRAPH_INTEROP_MUTATION_SCOPED=1 CARGO_BUILD_JOBS=1 \
    TMPDIR="$repository_tmp" \
    "$repository_root/scripts/run-mutation.sh"
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  printf '%s\n' 'mutation evidence requires a clean source commit' >&2
  exit 1
fi
if [[ "$(cargo mutants --version)" != 'cargo-mutants 27.1.0' ]]; then
  printf '%s\n' 'cargo-mutants 27.1.0 is required' >&2
  exit 1
fi

source_commit="$(git rev-parse HEAD)"
mkdir -p "$repository_root/target/mutation-runs"
run_directory="$(mktemp -d "$repository_root/target/mutation-runs/$source_commit.XXXXXXXX")"

{
  printf 'timestamp='; date --utc --iso-8601=seconds
  printf 'source_commit=%s\n' "$source_commit"
  printf 'run_directory=%s\n' "$run_directory"
  cargo mutants --version
  rustc -Vv
  cargo -V
} > "$metadata"

set +e
cargo mutants --cargo-arg=--locked -j 1 --jobserver-tasks 1 --timeout 120 \
  --copy-target=false --file 'src/*.rs' --output "$run_directory" \
  > "$evidence" 2>&1
mutation_status="$?"
set -e

result_directory="$run_directory/mutants.out"
for result_file in outcomes.json missed.txt timeout.txt; do
  if [[ ! -f "$result_directory/$result_file" ]]; then
    printf 'mutation result is missing %s\n' "$result_file" >&2
    exit 1
  fi
done
if [[ -s "$result_directory/missed.txt" || -s "$result_directory/timeout.txt" ]]; then
  printf '%s\n' 'mutation campaign has a survivor or timeout' >&2
  exit 1
fi
if ! jq -e '
    .cargo_mutants_version == "27.1.0"
    and .missed == 0
    and .timeout == 0
    and (.caught + .unviable == .total_mutants)
  ' "$result_directory/outcomes.json" >/dev/null; then
  printf '%s\n' 'mutation outcome totals do not prove complete disposition' >&2
  exit 1
fi
if [[ "$mutation_status" -ne 0 ]]; then
  printf 'cargo-mutants exited with status %s\n' "$mutation_status" >&2
  exit "$mutation_status"
fi

cp "$result_directory/outcomes.json" "$evidence_directory/mutation-outcomes.json"
cp "$result_directory/missed.txt" "$evidence_directory/mutation-missed.txt"
cp "$result_directory/timeout.txt" "$evidence_directory/mutation-timeout.txt"

jq -r '
  "mutation campaign passed \(.total_mutants) mutants: "
  + "\(.caught) caught, \(.unviable) unviable, 0 missed, 0 timed out"
' "$result_directory/outcomes.json"
