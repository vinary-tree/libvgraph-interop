#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
formal_source="${LIBVGRAPH_FORMAL_SOURCE:-$repository_root/../libvgraph-vco-e2-interop-formal}"
formal_commit='59952b0cccbdd32f18f2c13f87c539c7e5427e5d'
manifest="$repository_root/formal/contract.sha256"
allowed_signers="$repository_root/.github/allowed_signers"
expected_artifacts=(
  Cargo.lock
  Cargo.toml
  formal/doc/interop-invariants.tsv
  formal/model/exhaustive_interop.rs
  formal/rocq/GraphSnapshot.v
  formal/smt/interop_snapshot.smt2
  formal/tla/InteropCodecGrowNativeDepth.cfg
  formal/tla/InteropCodecIgnoreCancellation.cfg
  formal/tla/InteropCodecMachine.cfg
  formal/tla/InteropCodecMachine.tla
  formal/tla/InteropCodecSkipCanonical.cfg
  formal/tla/InteropCodecSkipSchema.cfg
  formal/tla/ReleaseMachine.cfg
  formal/tla/ReleaseMachine.tla
  formal/tla/ReleaseMachineCandidatePolicy.cfg
  formal/tla/ReleaseMachinePublishEarly.cfg
  formal/tla/ReleaseMachineRepublish.cfg
  formal/tla/ReleaseMachineSkipEvidence.cfg
  formal/tla/ReleaseMachineSkipGates.cfg
  formal/tla/ReleaseMachineSkipProtectedHead.cfg
  formal/tla/ReleaseMachineSkipRegistryChecksum.cfg
  formal/verus/interop_refinement.rs
  scripts/check-core-boundary.sh
  scripts/check-interop-invariants.sh
  scripts/verify-formal.sh
  tests/interop_contract_properties.rs
)

if [[ ! -d "$formal_source/.git" && ! -f "$formal_source/.git" ]]; then
  printf 'formal source is not a Git checkout: %s\n' "$formal_source" >&2
  exit 1
fi
if [[ ! -f "$allowed_signers" || -L "$allowed_signers" ]]; then
  printf 'formal signer policy must be a regular file: %s\n' "$allowed_signers" >&2
  exit 1
fi

git -C "$formal_source" cat-file -e "$formal_commit^{commit}"
git -C "$formal_source" \
  -c gpg.ssh.allowedSignersFile="$allowed_signers" \
  verify-commit "$formal_commit"

mapfile -t manifest_lines < "$manifest"
if [[ "${#manifest_lines[@]}" -ne "${#expected_artifacts[@]}" ]]; then
  printf 'expected %s canonical formal artifacts, found %s\n' \
    "${#expected_artifacts[@]}" "${#manifest_lines[@]}" >&2
  exit 1
fi

for artifact_index in "${!expected_artifacts[@]}"; do
  manifest_line="${manifest_lines[$artifact_index]}"
  if [[ ! "$manifest_line" =~ ^([0-9a-f]{64})\ \ ([A-Za-z0-9._/-]+)$ ]]; then
    printf 'malformed formal manifest line %s\n' "$((artifact_index + 1))" >&2
    exit 1
  fi
  expected_digest="${BASH_REMATCH[1]}"
  artifact_path="${BASH_REMATCH[2]}"
  if [[ "$artifact_path" != "${expected_artifacts[$artifact_index]}" ]]; then
    printf 'formal manifest line %s expected %s, found %s\n' \
      "$((artifact_index + 1))" "${expected_artifacts[$artifact_index]}" \
      "$artifact_path" >&2
    exit 1
  fi
  actual_digest="$(git -C "$formal_source" show "$formal_commit:$artifact_path" \
    | sha256sum | cut -d' ' -f1)"
  if [[ "$actual_digest" != "$expected_digest" ]]; then
    printf 'formal artifact digest mismatch: %s\n' "$artifact_path" >&2
    printf 'expected %s\nactual   %s\n' "$expected_digest" "$actual_digest" >&2
    exit 1
  fi
done

printf 'verified signed formal commit %s and %s canonical artifacts\n' \
  "$formal_commit" "${#expected_artifacts[@]}"
