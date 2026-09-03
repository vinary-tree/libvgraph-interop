#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'usage: %s VERSION TARGET_SUBDIRECTORY\n' "$0" >&2
  exit 2
fi

version="$1"
output_subdirectory="$2"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

manifest_version="$(
  cargo metadata --locked --no-deps --format-version 1 \
    | jq -er '.packages[] | select(.name == "libvgraph-interop") | .version'
)"
if [[ "$version" != "$manifest_version" ]]; then
  printf 'SBOM version %s differs from manifest version %s\n' \
    "$version" "$manifest_version" >&2
  exit 2
fi
if [[ "$output_subdirectory" != target/* || "$output_subdirectory" == *'/../'* \
    || "$output_subdirectory" == *'/..' || "$output_subdirectory" == */. \
    || "$output_subdirectory" == *'/./'* ]]; then
  printf 'SBOM output must be a canonical repository target subdirectory: %s\n' \
    "$output_subdirectory" >&2
  exit 2
fi
output_directory="$(realpath -m "$repository_root/$output_subdirectory")"
if [[ "$output_directory" != "$repository_root/target/"* ]]; then
  printf 'SBOM output escapes the repository target directory: %s\n' \
    "$output_directory" >&2
  exit 2
fi
mkdir -p "$output_directory"

if [[ "$(cargo cyclonedx --version)" != 'cargo-cyclonedx-cyclonedx 0.5.9' ]]; then
  printf '%s\n' 'cargo-cyclonedx-cyclonedx 0.5.9 is required' >&2
  exit 1
fi

generated_basename="libvgraph-interop-$version.release-sbom.cdx"
generated="$repository_root/$generated_basename.json"
normalized="$(mktemp "$output_directory/.libvgraph-interop-sbom.XXXXXXXX.json")"
output="$output_directory/libvgraph-interop-$version.cdx.json"
cleanup() {
  rm -f -- "$generated" "$normalized"
}
trap cleanup EXIT
if [[ -e "$generated" || -L "$generated" ]]; then
  printf 'cargo-cyclonedx intermediate already exists: %s\n' "$generated" >&2
  exit 1
fi

source_epoch="$(git show -s --format=%ct HEAD)"
if [[ ! "$source_epoch" =~ ^[1-9][0-9]*$ ]]; then
  printf 'source commit has an invalid epoch: %s\n' "$source_epoch" >&2
  exit 1
fi
SOURCE_DATE_EPOCH="$source_epoch" \
  cargo cyclonedx --format json --spec-version 1.5 \
    --override-filename "$generated_basename"

root_ref="$(jq -er '.metadata.component["bom-ref"]' "$generated")"
canonical_ref="pkg:cargo/libvgraph-interop@$version"
jq \
  --arg root_ref "$root_ref" \
  --arg canonical_ref "$canonical_ref" \
  '.metadata.component["bom-ref"] = $canonical_ref
    | .metadata.component.purl = $canonical_ref
    | .metadata.component.components = ((.metadata.component.components // [])
        | map(.["bom-ref"] = ($canonical_ref + "?target=" + (.name | @uri))
          | .purl = $canonical_ref))
    | .dependencies = ((.dependencies // [])
        | map(if .ref == $root_ref then .ref = $canonical_ref else . end))' \
  "$generated" > "$normalized"

jq -e \
  --arg version "$version" \
  --arg repository_root "$repository_root" \
  --arg canonical_ref "$canonical_ref" \
  '.bomFormat == "CycloneDX"
    and .specVersion == "1.5"
    and .metadata.component.name == "libvgraph-interop"
    and .metadata.component.version == $version
    and .metadata.component["bom-ref"] == $canonical_ref
    and .metadata.component.purl == $canonical_ref
    and (.metadata.component.components | all(.purl == $canonical_ref))
    and ([.dependencies[]? | select(.ref == $canonical_ref)] | length == 1)
    and ([.. | strings | select(contains($repository_root))] | length == 0)
    and ([.. | strings | select(contains("file://"))] | length == 0)
    and (([.metadata.component["bom-ref"]]
          + [.components[]?["bom-ref"]]) as $component_refs
      | [.dependencies[]? | .ref, .dependsOn[]?]
      | all(. as $ref | $component_refs | index($ref) != null))' \
  "$normalized" >/dev/null

if [[ -e "$output" || -L "$output" ]]; then
  if [[ ! -f "$output" || -L "$output" ]] || ! cmp -s "$normalized" "$output"; then
    printf 'existing SBOM differs from deterministic candidate: %s\n' "$output" >&2
    exit 1
  fi
else
  mv "$normalized" "$output"
fi
printf 'generated deterministic CycloneDX 1.5 SBOM: %s\n' "$output"
