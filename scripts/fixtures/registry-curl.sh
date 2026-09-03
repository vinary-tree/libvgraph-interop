#!/usr/bin/env bash
set -euo pipefail

output=
user_agent=
endpoint=
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output|--write-out|--user-agent|--proto)
      option="$1"
      value="$2"
      shift 2
      if [[ "$option" == --output ]]; then output="$value"; fi
      if [[ "$option" == --user-agent ]]; then user_agent="$value"; fi
      ;;
    --retry)
      shift 2
      ;;
    --silent|--show-error|--location|--tlsv1.2)
      shift
      ;;
    https://*)
      endpoint="$1"
      shift
      ;;
    *)
      printf 'unexpected curl argument: %s\n' "$1" >&2
      exit 64
      ;;
  esac
done
[[ "$user_agent" == \
  'libvgraph-interop-release/0.1 (+https://github.com/vinary-tree/libvgraph-interop)' ]]
[[ "$endpoint" == 'https://crates.io/api/v1/crates/libvgraph-interop/0.1.0' ]]
[[ -n "$output" ]]
case "${FAKE_CURL_CASE:-}" in
  present)
    jq -n --arg checksum "$FAKE_PACKAGE_SHA256" \
      '{version: {num: "0.1.0", checksum: $checksum}}' > "$output"
    printf '%s' 200
    ;;
  mismatch)
    jq -n '{version: {num: "0.1.0",
      checksum: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}}' \
      > "$output"
    printf '%s' 200
    ;;
  malformed)
    printf '%s\n' '{' > "$output"
    printf '%s' 200
    ;;
  absent)
    : > "$output"
    printf '%s' 404
    ;;
  unavailable)
    printf '%s\n' '{"errors":[{"detail":"unavailable"}]}' > "$output"
    printf '%s' 503
    ;;
  *)
    exit 64
    ;;
esac
