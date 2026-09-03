#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$#" -gt 1 ]]; then
  printf 'usage: %s [FORMAL_BINDING_FILE]\n' "$0" >&2
  exit 2
fi
binding_file="${1:-$repository_root/formal/source.commit}"

formal_source_binding_is_canonical() {
  local candidate="$1"
  local byte_count
  if [[ ! -f "$candidate" || -L "$candidate" ]]; then
    printf 'formal source binding must be a regular file: %s\n' "$candidate" >&2
    return 1
  fi
  byte_count="$(wc -c < "$candidate")"
  if [[ "$byte_count" -ne 41 ]]; then
    printf 'formal source binding must contain one 40-digit SHA and one newline: %s\n' \
      "$candidate" >&2
    return 1
  fi
  IFS= read -r formal_commit < "$candidate"
  if [[ ! "$formal_commit" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'formal source binding is not a lowercase 40-digit SHA: %s\n' \
      "$candidate" >&2
    return 1
  fi
  printf '%s\n' "$formal_commit"
}

formal_source_binding_is_canonical "$binding_file"
