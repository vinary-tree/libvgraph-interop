#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$repository_root/scripts/resolve-formal-commit.sh"
binding_checker="$repository_root/scripts/check-formal-source-binding.sh"
workflow_checker="$repository_root/scripts/check-formal-source-workflows.sh"
test_root="$repository_root/target/formal-source-binding-tests"
mkdir -p "$test_root"
run_directory="$(mktemp -d "$test_root/run.XXXXXXXX")"
trap 'rm -rf -- "$run_directory"' EXIT

expect_resolver_rejected() {
  local label="$1"
  local candidate="$2"
  if "$resolver" "$candidate" > "$run_directory/$label.log" 2>&1; then
    printf 'formal binding mutant unexpectedly resolved: %s\n' "$label" >&2
    exit 1
  fi
}

expected="$($resolver)"
valid_binding="$run_directory/valid.commit"
printf '%s\n' "$expected" > "$valid_binding"
[[ "$($resolver "$valid_binding")" == "$expected" ]]

hex_seed=0123456789abcdef0123456789abcdef01234567
for length in {0..39} {41..80}; do
  printf '%.*s\n' "$length" "$hex_seed$hex_seed$hex_seed" \
    > "$run_directory/length.commit"
  expect_resolver_rejected "length-$length" "$run_directory/length.commit"
done
for position in {0..39}; do
  printf '%s\n' "${expected:0:position}g${expected:position+1}" \
    > "$run_directory/character.commit"
  expect_resolver_rejected "character-$position" "$run_directory/character.commit"
done
printf '%s' "$expected" > "$run_directory/no-newline.commit"
expect_resolver_rejected no-newline "$run_directory/no-newline.commit"
printf '%s\n%s\n' "$expected" "$expected" > "$run_directory/two-lines.commit"
expect_resolver_rejected two-lines "$run_directory/two-lines.commit"
printf '%s\n' "${expected^^}" > "$run_directory/uppercase.commit"
expect_resolver_rejected uppercase "$run_directory/uppercase.commit"
ln -s "$valid_binding" "$run_directory/symlink.commit"
expect_resolver_rejected symlink "$run_directory/symlink.commit"

formal_fixture="$run_directory/formal"
mkdir "$formal_fixture"
git -C "$formal_fixture" init --quiet
git -C "$formal_fixture" config user.name 'Formal Binding Fixture'
git -C "$formal_fixture" config user.email 'formal-binding@example.invalid'
printf '%s\n' first > "$formal_fixture/state"
git -C "$formal_fixture" add state
git -C "$formal_fixture" -c commit.gpgsign=false commit --quiet -m first
first_commit="$(git -C "$formal_fixture" rev-parse HEAD)"
printf '%s\n' second > "$formal_fixture/state"
git -C "$formal_fixture" add state
git -C "$formal_fixture" -c commit.gpgsign=false commit --quiet -m second
second_commit="$(git -C "$formal_fixture" rev-parse HEAD)"
"$binding_checker" "$formal_fixture" "$second_commit" \
  > "$run_directory/matching-head.log"
if "$binding_checker" "$formal_fixture" "$first_commit" \
    > "$run_directory/stale-head.log" 2>&1; then
  printf '%s\n' 'stale but locally present formal commit unexpectedly matched HEAD' >&2
  exit 1
fi
if "$binding_checker" "$formal_fixture" 0000000000000000000000000000000000000000 \
    > "$run_directory/missing-commit.log" 2>&1; then
  printf '%s\n' 'missing formal commit unexpectedly matched checkout' >&2
  exit 1
fi

ci_mutant="$run_directory/ci.yml"
release_mutant="$run_directory/release.yml"
cp "$repository_root/.github/workflows/ci.yml" "$ci_mutant"
cp "$repository_root/.github/workflows/release.yml" "$release_mutant"
LIBVGRAPH_CI_WORKFLOW="$ci_mutant" \
LIBVGRAPH_RELEASE_WORKFLOW="$release_mutant" \
  "$workflow_checker" > "$run_directory/workflows-positive.log"
SEARCH='ref: ${{ steps.formal_source.outputs.commit }}' \
REPLACEMENT="ref: $expected" perl -0pi -e 's/\Q$ENV{SEARCH}\E/$ENV{REPLACEMENT}/' \
  "$ci_mutant"
if LIBVGRAPH_CI_WORKFLOW="$ci_mutant" \
    LIBVGRAPH_RELEASE_WORKFLOW="$release_mutant" \
    "$workflow_checker" > "$run_directory/direct-ref.log" 2>&1; then
  printf '%s\n' 'direct formal workflow ref mutant unexpectedly passed' >&2
  exit 1
fi
cp "$repository_root/.github/workflows/ci.yml" "$ci_mutant"
SEARCH='scripts/resolve-formal-commit.sh' \
REPLACEMENT='scripts/skip-formal-commit-resolution.sh' \
  perl -0pi -e 's/\Q$ENV{SEARCH}\E/$ENV{REPLACEMENT}/' "$release_mutant"
if LIBVGRAPH_CI_WORKFLOW="$ci_mutant" \
    LIBVGRAPH_RELEASE_WORKFLOW="$release_mutant" \
    "$workflow_checker" > "$run_directory/skipped-resolver.log" 2>&1; then
  printf '%s\n' 'skipped formal resolver workflow mutant unexpectedly passed' >&2
  exit 1
fi

printf '%s\n' \
  'verified canonical formal binding, checkout identity, and workflow consumption properties'
