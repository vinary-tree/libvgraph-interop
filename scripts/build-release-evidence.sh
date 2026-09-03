#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$#" -ne 1 ]] \
    || ! "$repository_root/scripts/validate-release-version.sh" "$1"; then
  printf 'usage: %s MAJOR.MINOR.PATCH\n' "$0" >&2
  exit 2
fi

version="$1"
evidence_directory="$repository_root/target/verification"
release_directory="$repository_root/target/release"
package="$repository_root/target/package/libvgraph-interop-$version.crate"
sbom="$release_directory/libvgraph-interop-$version.cdx.json"
source_commit="$(git -C "$repository_root" rev-parse HEAD)"
formal_commit="$("$repository_root/scripts/resolve-formal-commit.sh")"
stage_name="libvgraph-interop-$version-evidence-$source_commit"
stage="$release_directory/$stage_name"
bundle="$release_directory/$stage_name.tar"
asset_manifest="$release_directory/libvgraph-interop-$version-assets.sha256"
evidence_layout="$repository_root/scripts/release-evidence-files.txt"
mkdir -p "$release_directory"

if [[ -n "$(git -C "$repository_root" status --porcelain --untracked-files=all)" ]]; then
  printf '%s\n' 'release evidence requires a clean source commit' >&2
  exit 1
fi
manifest_version="$(cargo metadata --locked --no-deps --format-version 1 \
  | jq -er '.packages[] | select(.name == "libvgraph-interop") | .version')"
if [[ "$manifest_version" != "$version" ]]; then
  printf 'release version %s differs from manifest version %s\n' \
    "$version" "$manifest_version" >&2
  exit 1
fi
if [[ ! -f "$package" || -L "$package" ]]; then
  printf 'verified package is missing: %s\n' "$package" >&2
  exit 1
fi
if [[ ! -f "$sbom" || -L "$sbom" ]] \
    || ! jq -e --arg version "$version" \
      '.bomFormat == "CycloneDX"
        and .specVersion == "1.5"
        and .metadata.component.name == "libvgraph-interop"
        and .metadata.component.version == $version' "$sbom" >/dev/null; then
  printf 'valid CycloneDX JSON is missing: %s\n' "$sbom" >&2
  exit 1
fi
if [[ -e "$stage" || -e "$bundle" || -e "$asset_manifest" ]]; then
  printf '%s\n' 'release evidence output already exists; use a clean target directory' >&2
  exit 1
fi

if [[ ! -f "$evidence_layout" || -L "$evidence_layout" ]] \
    || grep -E -v -q '^[A-Za-z0-9][A-Za-z0-9._-]*$' "$evidence_layout" \
    || [[ "$(sort "$evidence_layout" | uniq -d | wc -l)" -ne 0 ]]; then
  printf 'release evidence layout is invalid: %s\n' "$evidence_layout" >&2
  exit 1
fi
mapfile -t required_evidence < "$evidence_layout"
for evidence_name in "${required_evidence[@]}"; do
  evidence_path="$evidence_directory/$evidence_name"
  if [[ ! -f "$evidence_path" || -L "$evidence_path" ]]; then
    printf 'required release evidence is missing: %s\n' "$evidence_path" >&2
    exit 1
  fi
done
registry_evidence="$evidence_directory/crates-io-libvgraph-interop-$version.json"
package_sha256="$(sha256sum "$package" | cut -d' ' -f1)"
if [[ ! -f "$registry_evidence" || -L "$registry_evidence" ]] \
    || ! jq -e --arg version "$version" \
      --arg package_sha256 "$package_sha256" \
      '.version.num == $version and .version.checksum == $package_sha256' \
      "$registry_evidence" >/dev/null; then
  printf 'final crates.io registry evidence is invalid: %s\n' \
    "$registry_evidence" >&2
  exit 1
fi

mkdir "$stage"
stage_incomplete=1
trap 'if [[ "$stage_incomplete" -eq 1 ]]; then rm -rf -- "$stage"; rm -f -- "$bundle" "$asset_manifest"; fi' EXIT
for evidence_name in "${required_evidence[@]}"; do
  evidence_path="$evidence_directory/$evidence_name"
  cp "$evidence_path" "$stage/$evidence_name"
done
cp "$registry_evidence" "$stage/$(basename "$registry_evidence")"
cp "$repository_root/formal/contract.sha256" "$stage/formal-contract.sha256"
cp "$repository_root/formal/refinement.tsv" "$stage/formal-refinement.tsv"
cp "$repository_root/docs/diagrams/rendered.sha256" "$stage/rendered-diagrams.sha256"

sbom_sha256="$(sha256sum "$sbom")"
sbom_sha256="${sbom_sha256%% *}"
source_epoch="$(git -C "$repository_root" show -s --format=%ct HEAD)"
jq -n \
  --arg schema 'libvgraph-interop-release-evidence-v1' \
  --arg crate_version "$version" \
  --arg source_commit "$source_commit" \
  --arg formal_commit "$formal_commit" \
  --arg package_sha256 "$package_sha256" \
  --arg sbom_sha256 "$sbom_sha256" \
  --argjson source_epoch "$source_epoch" \
  '{schema: $schema, crate_version: $crate_version, source_commit: $source_commit,
    formal_commit: $formal_commit, source_epoch: $source_epoch,
    package_sha256: $package_sha256, sbom_sha256: $sbom_sha256}' \
  > "$stage/evidence.json"

mapfile -d '' staged_files < <(
  cd "$stage"
  find . -type f ! -name SHA256SUMS -print0 | sort -z
)
(
  cd "$stage"
  for staged_file in "${staged_files[@]}"; do
    sha256sum "$staged_file"
  done
) > "$stage/SHA256SUMS"

tar --sort=name --format=posix \
  --pax-option=delete=atime,delete=ctime \
  --mtime="@$source_epoch" --owner=0 --group=0 --numeric-owner \
  -cf "$bundle" -C "$release_directory" "$stage_name"

for asset in "$package" "$sbom" "$bundle"; do
  asset_sha256="$(sha256sum "$asset")"
  asset_sha256="${asset_sha256%% *}"
  printf '%s  %s\n' "$asset_sha256" "$(basename "$asset")"
done > "$asset_manifest"

sha256sum --check "$stage/SHA256SUMS" >/dev/null
stage_incomplete=0
trap - EXIT
printf 'built deterministic release evidence for %s at %s\n' "$source_commit" "$bundle"
