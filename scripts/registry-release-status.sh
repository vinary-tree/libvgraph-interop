#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  printf 'usage: %s CRATE VERSION PACKAGE.crate\n' "$0" >&2
  exit 2
fi

crate="$1"
version="$2"
package="$3"
if [[ ! -f "$package" ]]; then
  printf 'package does not exist: %s\n' "$package" >&2
  exit 2
fi

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
evidence_directory="$repository_root/target/verification"
mkdir -p "$evidence_directory"
response="$evidence_directory/crates-io-$crate-$version.json"
http_status="$(curl --silent --show-error --location --retry 3 \
  --proto '=https' --tlsv1.2 --output "$response" --write-out '%{http_code}' \
  "https://crates.io/api/v1/crates/$crate/$version")"

case "$http_status" in
  200)
    expected="$(jq -er '.version.checksum' "$response")"
    actual="$(sha256sum "$package")"
    actual="${actual%% *}"
    if [[ "$actual" != "$expected" ]]; then
      printf 'registry checksum mismatch for %s %s\nexpected %s\nactual   %s\n' \
        "$crate" "$version" "$expected" "$actual" >&2
      exit 1
    fi
    printf '%s\n' present
    ;;
  404)
    printf '%s\n' absent
    ;;
  *)
    printf 'unexpected crates.io status %s for %s %s\n' \
      "$http_status" "$crate" "$version" >&2
    exit 1
    ;;
esac
