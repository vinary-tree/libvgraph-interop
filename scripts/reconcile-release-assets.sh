#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 4 ]]; then
  printf 'usage: %s MAJOR.MINOR.PATCH TAG RELEASE_ID draft|published\n' "$0" >&2
  exit 2
fi

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$1"
tag="$2"
release_id="$3"
release_state="$4"
if ! "$repository_root/scripts/validate-release-version.sh" "$version"; then
  printf 'invalid release version: %s\n' "$version" >&2
  exit 2
fi
if [[ "$tag" != "v$version" || ! "$release_id" =~ ^[1-9][0-9]*$ ]]; then
  printf 'release identity is inconsistent: %s %s %s\n' \
    "$version" "$tag" "$release_id" >&2
  exit 2
fi
if [[ "$release_state" != draft && "$release_state" != published ]]; then
  printf 'invalid release state: %s\n' "$release_state" >&2
  exit 2
fi
if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  printf '%s\n' 'GITHUB_REPOSITORY is required' >&2
  exit 2
fi

release_directory="$repository_root/target/release"
evidence_directory="$repository_root/target/verification"
source_commit="$(git -C "$repository_root" rev-parse HEAD)"
package_name="libvgraph-interop-$version.crate"
sbom_name="libvgraph-interop-$version.cdx.json"
evidence_name="libvgraph-interop-$version-evidence-$source_commit.tar"
manifest_name="libvgraph-interop-$version-assets.sha256"
package="$repository_root/target/package/$package_name"
sbom="$release_directory/$sbom_name"
evidence_bundle="$release_directory/$evidence_name"
asset_manifest="$release_directory/$manifest_name"
release_json="$evidence_directory/github-release-before-assets.json"
evidence_layout="$repository_root/scripts/release-evidence-files.txt"
mkdir -p "$release_directory" "$evidence_directory"

if [[ ! -f "$evidence_layout" || -L "$evidence_layout" ]] \
    || rg -v -q '^[A-Za-z0-9][A-Za-z0-9._-]*$' "$evidence_layout" \
    || [[ "$(sort "$evidence_layout" | uniq -d | wc -l)" -ne 0 ]]; then
  printf 'release evidence layout is invalid: %s\n' "$evidence_layout" >&2
  exit 1
fi
mapfile -t required_evidence < "$evidence_layout"

for local_asset in "$package" "$sbom" "$evidence_bundle" "$asset_manifest"; do
  if [[ ! -f "$local_asset" || -L "$local_asset" ]]; then
    printf 'release asset must be a regular file: %s\n' "$local_asset" >&2
    exit 1
  fi
done

download_directory="$(mktemp -d "$release_directory/reconcile.XXXXXXXX")"
trap 'rm -rf -- "$download_directory"' EXIT

fetch_release() {
  gh api "repos/${GITHUB_REPOSITORY}/releases/$release_id" > "$release_json"
  jq -e \
    --arg tag "$tag" \
    --arg state "$release_state" \
    --argjson release_id "$release_id" \
    '.id == $release_id
      and .tag_name == $tag
      and (.draft == ($state == "draft"))
      and ((.assets | map(.name) | length) == (.assets | map(.name) | unique | length))
      and (.assets | all(.state == "uploaded"))
      and (($state != "published") or .immutable == true)' \
    "$release_json" >/dev/null
}

asset_present() {
  local asset_name="$1"
  jq -e --arg name "$asset_name" '.assets | any(.name == $name)' \
    "$release_json" >/dev/null
}

download_asset() {
  local asset_name="$1"
  local destination="$2"
  local asset_id
  asset_id="$(jq -er --arg name "$asset_name" \
    '.assets[] | select(.name == $name) | .id' "$release_json")"
  gh api -H 'Accept: application/octet-stream' \
    "repos/${GITHUB_REPOSITORY}/releases/assets/$asset_id" > "$destination"
}

validate_expected_names() {
  local existing_name
  while IFS= read -r existing_name; do
    case "$existing_name" in
      "$package_name"|"$sbom_name"|"$evidence_name"|"$manifest_name") ;;
      *)
        printf 'release contains unexpected asset: %s\n' "$existing_name" >&2
        return 1
        ;;
    esac
  done < <(jq -r '.assets[].name' "$release_json")
}

validate_evidence_bundle() {
  local candidate_bundle="$1"
  local stage_name="libvgraph-interop-$version-evidence-$source_commit"
  local extracted
  local archive_entry
  local archive_mode
  local relative_entry
  local -a duplicate_entries
  extracted="$(mktemp -d "$download_directory/extracted.XXXXXXXX")"

  mapfile -t duplicate_entries < <(tar -tf "$candidate_bundle" | sort | uniq -d)
  if [[ "${#duplicate_entries[@]}" -ne 0 ]]; then
    printf 'evidence archive contains duplicate entries:\n%s\n' \
      "${duplicate_entries[*]}" >&2
    return 1
  fi

  while IFS= read -r archive_entry; do
    if [[ "$archive_entry" != "$stage_name" \
        && "$archive_entry" != "$stage_name/" \
        && "$archive_entry" != "$stage_name/"* ]]; then
      printf 'evidence archive contains an out-of-root path: %s\n' \
        "$archive_entry" >&2
      return 1
    fi
    if [[ "$archive_entry" == /* || "$archive_entry" == *'/../'* \
        || "$archive_entry" == '../'* ]]; then
      printf 'evidence archive contains an unsafe path: %s\n' "$archive_entry" >&2
      return 1
    fi
    relative_entry="${archive_entry#"$stage_name"}"
    relative_entry="${relative_entry#/}"
    if [[ -n "$relative_entry" && "$relative_entry" == */* ]]; then
      printf 'evidence archive contains a nested path: %s\n' "$archive_entry" >&2
      return 1
    fi
  done < <(tar -tf "$candidate_bundle")

  while IFS= read -r archive_mode; do
    if [[ "${archive_mode:0:1}" != - && "${archive_mode:0:1}" != d ]]; then
      printf 'evidence archive contains a non-regular entry: %s\n' \
        "$archive_mode" >&2
      return 1
    fi
  done < <(tar -tvf "$candidate_bundle")

  tar --extract --file "$candidate_bundle" --directory "$extracted" \
    --no-same-owner --no-same-permissions
  local stage="$extracted/$stage_name"
  if [[ ! -d "$stage" || -n "$(find "$stage" -mindepth 1 ! -type f -print -quit)" ]]; then
    printf '%s\n' 'evidence archive root is missing or contains a non-regular entry' >&2
    return 1
  fi
  if [[ ! -f "$stage/evidence.json" || ! -f "$stage/SHA256SUMS" ]]; then
    printf '%s\n' 'evidence archive omits its metadata or internal manifest' >&2
    return 1
  fi

  jq -e \
    --arg version "$version" \
    --arg source_commit "$source_commit" \
    --arg formal_commit '59952b0cccbdd32f18f2c13f87c539c7e5427e5d' \
    --arg package_sha256 "$(sha256sum "$package" | cut -d' ' -f1)" \
    --arg sbom_sha256 "$(sha256sum "$sbom" | cut -d' ' -f1)" \
    '.schema == "libvgraph-interop-release-evidence-v1"
      and .crate_version == $version
      and .source_commit == $source_commit
      and .formal_commit == $formal_commit
      and .package_sha256 == $package_sha256
      and .sbom_sha256 == $sbom_sha256' \
    "$stage/evidence.json" >/dev/null

  if [[ ! -s "$stage/SHA256SUMS" ]] \
      || rg -v -q '^[0-9a-f]{64}  \./[A-Za-z0-9._-]+$' "$stage/SHA256SUMS"; then
    printf '%s\n' 'evidence archive contains a malformed internal manifest entry' >&2
    return 1
  fi
  awk '{ print $2 }' "$stage/SHA256SUMS" | sort > "$download_directory/manifest-files"
  (
    cd "$stage"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%p\n' | sort
  ) > "$download_directory/actual-files"
  if ! diff -u "$download_directory/manifest-files" \
      "$download_directory/actual-files"; then
    printf '%s\n' 'evidence archive file set differs from its internal manifest' >&2
    return 1
  fi
  {
    for required_name in "${required_evidence[@]}"; do
      printf './%s\n' "$required_name"
    done
    printf './%s\n' \
      "crates-io-libvgraph-interop-$version.json" \
      evidence.json \
      formal-contract.sha256 \
      formal-refinement.tsv \
      rendered-diagrams.sha256
  } | sort > "$download_directory/expected-files"
  if ! diff -u "$download_directory/expected-files" \
      "$download_directory/actual-files"; then
    printf '%s\n' 'evidence archive does not contain the exact required evidence set' >&2
    return 1
  fi
  if ! cmp -s "$stage/formal-contract.sha256" \
      "$repository_root/formal/contract.sha256" \
      || ! cmp -s "$stage/formal-refinement.tsv" \
        "$repository_root/formal/refinement.tsv" \
      || ! cmp -s "$stage/rendered-diagrams.sha256" \
        "$repository_root/docs/diagrams/rendered.sha256"; then
    printf '%s\n' 'evidence archive formal or diagram bindings differ from the candidate' >&2
    return 1
  fi
  if ! jq -e --arg version "$version" \
      --arg package_sha256 "$(sha256sum "$package" | cut -d' ' -f1)" \
      '.version.num == $version and .version.checksum == $package_sha256' \
      "$stage/crates-io-libvgraph-interop-$version.json" >/dev/null; then
    printf '%s\n' 'evidence archive registry binding differs from the candidate package' >&2
    return 1
  fi
  (
    cd "$stage"
    sha256sum --check SHA256SUMS >/dev/null
  )
}

write_asset_manifest() {
  for local_asset in "$package" "$sbom" "$evidence_bundle"; do
    local asset_sha256
    asset_sha256="$(sha256sum "$local_asset" | cut -d' ' -f1)"
    printf '%s  %s\n' "$asset_sha256" "$(basename "$local_asset")"
  done > "$asset_manifest"
}

fetch_release
validate_expected_names

for immutable_asset in "$package" "$sbom"; do
  immutable_name="$(basename "$immutable_asset")"
  if asset_present "$immutable_name"; then
    downloaded="$download_directory/$immutable_name"
    download_asset "$immutable_name" "$downloaded"
    if ! cmp -s "$immutable_asset" "$downloaded"; then
      printf 'existing release asset differs from candidate: %s\n' \
        "$immutable_name" >&2
      exit 1
    fi
  fi
done

if asset_present "$evidence_name"; then
  downloaded_evidence="$download_directory/$evidence_name"
  download_asset "$evidence_name" "$downloaded_evidence"
  validate_evidence_bundle "$downloaded_evidence"
  cp "$downloaded_evidence" "$evidence_bundle"
fi
validate_evidence_bundle "$evidence_bundle"
write_asset_manifest

if asset_present "$manifest_name"; then
  downloaded_manifest="$download_directory/$manifest_name"
  download_asset "$manifest_name" "$downloaded_manifest"
  if ! cmp -s "$asset_manifest" "$downloaded_manifest"; then
    printf '%s\n' 'existing release asset manifest differs from the candidate assets' >&2
    exit 1
  fi
fi

expected_assets=("$package" "$sbom" "$evidence_bundle" "$asset_manifest")
if [[ "$release_state" == published ]]; then
  for expected_asset in "${expected_assets[@]}"; do
    if ! asset_present "$(basename "$expected_asset")"; then
      printf 'published release is missing immutable asset: %s\n' \
        "$(basename "$expected_asset")" >&2
      exit 1
    fi
  done
else
  for expected_asset in "${expected_assets[@]}"; do
    expected_name="$(basename "$expected_asset")"
    if ! asset_present "$expected_name"; then
      gh release upload "$tag" "$expected_asset" --repo "$GITHUB_REPOSITORY"
      fetch_release
      validate_expected_names
    fi
  done
fi

fetch_release
validate_expected_names
if [[ "$(jq '.assets | length' "$release_json")" -ne 4 ]]; then
  printf '%s\n' 'release does not contain exactly four canonical assets' >&2
  exit 1
fi
for expected_asset in "${expected_assets[@]}"; do
  expected_name="$(basename "$expected_asset")"
  downloaded_final="$download_directory/final-$expected_name"
  download_asset "$expected_name" "$downloaded_final"
  if ! cmp -s "$expected_asset" "$downloaded_final"; then
    printf 'uploaded release asset failed byte-for-byte verification: %s\n' \
      "$expected_name" >&2
    exit 1
  fi
done

printf 'verified four complete immutable release assets for %s in %s state\n' \
  "$tag" "$release_state"
