#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'usage: %s MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]\n' "$0" >&2
  exit 2
fi

version="$1"
core='(0|[1-9][0-9]*)'
prerelease_identifier='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
pattern="^${core}\\.${core}\\.${core}(-${prerelease_identifier}(\\.${prerelease_identifier})*)?(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$"
if [[ ! "$version" =~ $pattern ]]; then
  printf 'invalid canonical SemVer 2.0.0 release version: %s\n' "$version" >&2
  exit 1
fi
