#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bootstrap_tools=(
  awk
  bash
  cut
  diff
  dirname
  git
  grep
  head
  mkdir
  sha256sum
  sort
  uniq
  wc
)

complete_tools=(
  awk
  basename
  bash
  cargo
  chmod
  cmp
  comm
  cp
  curl
  cut
  diff
  dirname
  env
  find
  git
  grep
  head
  java
  jq
  ln
  mkdir
  mktemp
  mv
  perl
  realpath
  rm
  rustc
  rustdoc
  rustfmt
  sed
  sha256sum
  sort
  tar
  tee
  tr
  uniq
  wc
  xargs
  yamllint
)

portable_tool_closure_is_explicit() {
  local command_name
  local -a missing=()
  for command_name in "$@"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing+=("$command_name")
    fi
  done
  if [[ "${#missing[@]}" -ne 0 ]]; then
    printf 'portable verification is missing required commands: %s\n' \
      "${missing[*]}" >&2
    return 1
  fi
}

verify_complete_plugins() {
  if [[ "$(cargo cyclonedx --version)" != 'cargo-cyclonedx-cyclonedx 0.5.9' ]]; then
    printf '%s\n' 'portable verification requires cargo-cyclonedx-cyclonedx 0.5.9' >&2
    return 1
  fi
  cargo deny --version >/dev/null
  local provisioned_tool
  for provisioned_tool in \
      actionlint shellcheck vinary-doc-lint-0.1.1-linux-x86_64; do
    if [[ ! -x "$repository_root/target/verification-tools/$provisioned_tool" ]]; then
      printf 'portable verification tool is missing or not executable: %s\n' \
        "$provisioned_tool" >&2
      return 1
    fi
  done
}

actionlint_is_isolated_from_system_shellcheck() {
  local verifier="${1:-$repository_root/scripts/verify-portable.sh}"
  local expected="run_gate actionlint \"\$repository_root/target/verification-tools/actionlint\" -shellcheck="
  if [[ ! -f "$verifier" || -L "$verifier" ]] \
      || [[ "$(grep -F -x -c -- "$expected" "$verifier" || true)" -ne 1 ]]; then
    printf 'portable verifier must disable actionlint system-ShellCheck discovery: %s\n' \
      "$verifier" >&2
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "$#" -ne 1 ]]; then
    printf 'usage: %s bootstrap|complete\n' "$0" >&2
    exit 2
  fi
  case "$1" in
    bootstrap)
      portable_tool_closure_is_explicit "${bootstrap_tools[@]}"
      ;;
    complete)
      portable_tool_closure_is_explicit "${complete_tools[@]}"
      verify_complete_plugins
      actionlint_is_isolated_from_system_shellcheck
      ;;
    *)
      printf 'unknown portable tool-closure phase: %s\n' "$1" >&2
      exit 2
      ;;
  esac
  printf 'verified %s portable tool dependency closure\n' "$1"
fi
