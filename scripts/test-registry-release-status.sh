#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$repository_root/target/registry-release-status-tests"
mkdir -p "$test_root"
run_directory="$(mktemp -d "$test_root/run.XXXXXXXX")"
trap 'rm -rf -- "$run_directory"' EXIT
fake_bin="$run_directory/bin"
mkdir "$fake_bin"
cp "$repository_root/scripts/fixtures/registry-curl.sh" "$fake_bin/curl"
chmod +x "$fake_bin/curl"

package="$run_directory/libvgraph-interop-0.1.0.crate"
printf '%s\n' 'deterministic package fixture' > "$package"
FAKE_PACKAGE_SHA256="$(sha256sum "$package" | cut -d' ' -f1)"
export FAKE_PACKAGE_SHA256

run_case() {
  local case_name="$1"
  PATH="$fake_bin:$PATH" FAKE_CURL_CASE="$case_name" \
    "$repository_root/scripts/registry-release-status.sh" \
      libvgraph-interop 0.1.0 "$package"
}

if [[ "$(run_case present)" != present ]]; then
  printf '%s\n' 'matching registry response was not admitted as present' >&2
  exit 1
fi
if [[ "$(run_case absent)" != absent ]]; then
  printf '%s\n' 'registry 404 was not classified as absent' >&2
  exit 1
fi
for rejected_case in mismatch malformed unavailable; do
  if run_case "$rejected_case" > "$run_directory/$rejected_case.log" 2>&1; then
    printf 'registry case unexpectedly passed: %s\n' "$rejected_case" >&2
    exit 1
  fi
done
if "$repository_root/scripts/registry-release-status.sh" \
    libvgraph-interop 0.1.0 "$run_directory/missing.crate" \
    > "$run_directory/missing.log" 2>&1; then
  printf '%s\n' 'registry check accepted a missing package' >&2
  exit 1
fi

printf '%s\n' \
  'verified authenticated registry request, present/absent states, and four rejection cases'
