#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$repository_root/scripts/validate-release-version.sh"
test_root="$repository_root/target/release-version-tests"
mkdir -p "$test_root"
run_directory="$(mktemp -d "$test_root/run.XXXXXXXX")"
trap 'rm -rf -- "$run_directory"' EXIT

valid_versions=(
  0.0.0
  1.2.3
  1.0.0-alpha
  1.0.0-alpha.1
  1.0.0-0.3.7
  1.0.0-x.7.z.92
  1.0.0-x-y-z.--
  1.0.0+build.01
  1.0.0-alpha+build-x.01
)
invalid_versions=(
  ''
  1
  1.2
  v1.2.3
  01.2.3
  1.02.3
  1.2.03
  1.2.3-01
  1.2.3-alpha..1
  1.2.3-
  1.2.3+
  1.2.3+build..1
  1.2.3_alpha
  1.2.3+build_1
)

for version in "${valid_versions[@]}"; do
  if ! "$validator" "$version" > "$run_directory/valid.log" 2>&1; then
    printf 'canonical SemVer was rejected: %s\n' "$version" >&2
    exit 1
  fi
done
for version in "${invalid_versions[@]}"; do
  if "$validator" "$version" > "$run_directory/invalid.log" 2>&1; then
    printf 'noncanonical release version was accepted: %s\n' "$version" >&2
    exit 1
  fi
done
if "$validator" > "$run_directory/missing.log" 2>&1 \
    || "$validator" 1.2.3 2.0.0 > "$run_directory/excess.log" 2>&1; then
  printf '%s\n' 'release version validator accepted an invalid arity' >&2
  exit 1
fi

printf 'verified %s canonical and %s noncanonical SemVer cases plus arity\n' \
  "${#valid_versions[@]}" "${#invalid_versions[@]}"
