#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
formal_source="${LIBVGRAPH_FORMAL_SOURCE:-$repository_root/../libvgraph-vco-e2-interop-formal}"
formal_commit='83e1cdd489369dcd7d53fb8fdf6041ef3f5cb697'
ledger="$repository_root/formal/refinement.tsv"
manifest="$repository_root/formal/contract.sha256"
evidence_directory="$repository_root/target/verification"
formal_ledger="$evidence_directory/frozen-formal-invariants.tsv"
formal_projection="$evidence_directory/frozen-formal-projection.tsv"
refinement_projection="$evidence_directory/refinement-formal-projection.tsv"
mkdir -p "$evidence_directory"

expected_header=$'invariant_id\tformal_layer\tformal_artifact\tformal_symbol\tproduction_artifact\tproduction_symbol'
if [[ "$(head -n 1 "$ledger")" != "$expected_header" ]]; then
  printf '%s\n' 'refinement ledger header is not canonical' >&2
  exit 1
fi

git -C "$formal_source" show "$formal_commit:formal/doc/interop-invariants.tsv" \
  > "$formal_ledger"
awk -F '\t' '
  BEGIN { OFS = "\t" }
  NR == 1 { next }
  NF != 6 { printf "formal invariant row %s has %s fields, expected 6\n", NR, NF > "/dev/stderr"; exit 1 }
  { print $1, $3, $4, $5 }
' "$formal_ledger" > "$formal_projection"
awk -F '\t' '
  BEGIN { OFS = "\t" }
  NR == 1 { next }
  NF != 6 { printf "refinement row %s has %s fields, expected 6\n", NR, NF > "/dev/stderr"; exit 1 }
  { print $1, $2, $3, $4 }
' "$ledger" > "$refinement_projection"
if ! diff -u "$formal_projection" "$refinement_projection"; then
  printf '%s\n' 'frozen formal invariants and refinement mappings differ' >&2
  exit 1
fi

row_count="$(wc -l < "$refinement_projection")"
if [[ "$row_count" -ne 75 ]]; then
  printf 'expected exactly 75 refinement rows, found %s\n' "$row_count" >&2
  exit 1
fi

declare -A manifested_artifacts=()
while read -r _ artifact_path; do
  manifested_artifacts["$artifact_path"]=1
done < "$manifest"

expected_id=1
while IFS=$'\t' read -r invariant_id formal_layer formal_artifact formal_symbol \
    production_artifact production_symbol; do
  if [[ "$invariant_id" == invariant_id ]]; then
    continue
  fi
  expected="$(printf 'INT-%03d' "$expected_id")"
  if [[ "$invariant_id" != "$expected" ]]; then
    printf 'expected invariant %s, found %s\n' "$expected" "$invariant_id" >&2
    exit 1
  fi
  if [[ -z "$formal_layer" || -z "$formal_artifact" || -z "$formal_symbol" \
      || -z "$production_artifact" || -z "$production_symbol" ]]; then
    printf '%s has an empty refinement field\n' "$invariant_id" >&2
    exit 1
  fi
  if [[ -z "${manifested_artifacts[$formal_artifact]+present}" ]]; then
    printf '%s references an unhashed formal artifact: %s\n' \
      "$invariant_id" "$formal_artifact" >&2
    exit 1
  fi
  if ! git -C "$formal_source" grep -F -q -e "$formal_symbol" \
      "$formal_commit" -- "$formal_artifact"; then
    printf '%s references missing frozen formal symbol %s in %s\n' \
      "$invariant_id" "$formal_symbol" "$formal_artifact" >&2
    exit 1
  fi
  production_path="$repository_root/$production_artifact"
  if [[ ! -f "$production_path" ]]; then
    printf 'missing production artifact for %s: %s\n' "$invariant_id" "$production_path" >&2
    exit 1
  fi
  if ! grep -F -q -- "$production_symbol" "$production_path"; then
    printf 'missing production symbol for %s: %s in %s\n' \
      "$invariant_id" "$production_symbol" "$production_path" >&2
    exit 1
  fi
  expected_id=$((expected_id + 1))
done < "$ledger"

if grep -R -E -n '(^|[^[:alnum:]_])(TODO|FIXME|HACK|XXX|PENDING)($|[^[:alnum:]_])' \
  "$repository_root/src" "$repository_root/tests" "$repository_root/formal"; then
  printf '%s\n' 'incomplete marker found in a refinement artifact' >&2
  exit 1
fi

printf 'verified %s bidirectional formal-to-production refinements at %s\n' \
  "$row_count" "$formal_commit"
