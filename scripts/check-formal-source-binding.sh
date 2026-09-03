#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'usage: %s FORMAL_SOURCE FORMAL_COMMIT\n' "$0" >&2
  exit 2
fi
formal_source="$1"
formal_commit="$2"

formal_source_matches_binding() {
  local source="$1"
  local expected="$2"
  local actual
  if [[ ! "$expected" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'formal source commit is not a lowercase 40-digit SHA: %s\n' "$expected" >&2
    return 1
  fi
  if [[ ! -d "$source/.git" && ! -f "$source/.git" ]]; then
    printf 'formal source is not a Git checkout: %s\n' "$source" >&2
    return 1
  fi
  if ! git -C "$source" cat-file -e "$expected^{commit}"; then
    printf 'bound formal commit is absent from checkout: %s\n' "$expected" >&2
    return 1
  fi
  actual="$(git -C "$source" rev-parse --verify 'HEAD^{commit}')"
  if [[ "$actual" != "$expected" ]]; then
    printf 'formal source HEAD differs from binding: expected %s, found %s\n' \
      "$expected" "$actual" >&2
    return 1
  fi
}

formal_source_matches_binding "$formal_source" "$formal_commit"
printf 'verified formal source HEAD at %s\n' "$formal_commit"
