#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$repository_root/target/release-sbom-tests"
mkdir -p "$test_root"
run_directory="$(mktemp -d "$test_root/run.XXXXXXXX")"
trap 'rm -rf -- "$run_directory"' EXIT
relative_run_directory="${run_directory#"$repository_root/"}"
version="$(
  cargo metadata --locked --no-deps --format-version 1 \
    | jq -er '.packages[] | select(.name == "libvgraph-interop") | .version'
)"
output="$run_directory/libvgraph-interop-$version.cdx.json"

"$repository_root/scripts/generate-release-sbom.sh" \
  "$version" "$relative_run_directory" > "$run_directory/first.log" 2>&1
first_sha256="$(sha256sum "$output" | cut -d' ' -f1)"
"$repository_root/scripts/generate-release-sbom.sh" \
  "$version" "$relative_run_directory" > "$run_directory/second.log" 2>&1
second_sha256="$(sha256sum "$output" | cut -d' ' -f1)"
if [[ "$first_sha256" != "$second_sha256" ]]; then
  printf '%s\n' 'identical source and epoch produced different SBOM bytes' >&2
  exit 1
fi
if jq -e --arg root "$repository_root" \
    '[.. | strings | select(contains($root))] | length != 0' "$output" >/dev/null; then
  printf '%s\n' 'release SBOM leaks its machine-specific repository path' >&2
  exit 1
fi
if jq -e '[.. | strings | select(contains("file://"))] | length != 0' \
    "$output" >/dev/null; then
  printf '%s\n' 'release SBOM contains a local-file reference' >&2
  exit 1
fi

printf '%s\n' tampered > "$output"
if "$repository_root/scripts/generate-release-sbom.sh" \
    "$version" "$relative_run_directory" \
    > "$run_directory/tampered.log" 2>&1; then
  printf '%s\n' 'SBOM generator replaced a differing existing artifact' >&2
  exit 1
fi
if "$repository_root/scripts/generate-release-sbom.sh" \
    "$version" ../outside-target \
    > "$run_directory/path-escape.log" 2>&1; then
  printf '%s\n' 'SBOM generator accepted an output path outside target' >&2
  exit 1
fi

printf '%s\n' \
  'verified deterministic, path-independent, fail-closed CycloneDX generation'
