#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$repository_root/target/reconcile-release-assets-tests"
mkdir -p "$test_root"
run_directory="$(mktemp -d "$test_root/run.XXXXXXXX")"
trap 'rm -rf -- "$run_directory"' EXIT

fixture="$run_directory/repository"
remote_assets="$run_directory/remote-assets"
good_remote_assets="$run_directory/good-remote-assets"
upload_log="$run_directory/uploads.log"
mkdir -p \
  "$fixture/scripts" \
  "$fixture/formal" \
  "$fixture/docs/diagrams" \
  "$fixture/target/package" \
  "$fixture/target/release" \
  "$fixture/target/verification" \
  "$remote_assets"
cp "$repository_root/scripts/reconcile-release-assets.sh" "$fixture/scripts/"
cp "$repository_root/scripts/release-evidence-files.txt" "$fixture/scripts/"
cp "$repository_root/scripts/validate-release-version.sh" "$fixture/scripts/"
cp "$repository_root/formal/contract.sha256" "$fixture/formal/"
cp "$repository_root/formal/refinement.tsv" "$fixture/formal/"
cp "$repository_root/docs/diagrams/rendered.sha256" "$fixture/docs/diagrams/"
printf '%s\n' fixture > "$fixture/fixture-marker"
git -C "$fixture" init --quiet
git -C "$fixture" config user.name 'Release Fixture'
git -C "$fixture" config user.email 'release-fixture@example.invalid'
git -C "$fixture" add .
git -C "$fixture" commit --quiet -m 'Create release reconciliation fixture'

version=0.1.0
tag="v$version"
release_id=42
source_commit="$(git -C "$fixture" rev-parse HEAD)"
package_name="libvgraph-interop-$version.crate"
sbom_name="libvgraph-interop-$version.cdx.json"
evidence_name="libvgraph-interop-$version-evidence-$source_commit.tar"
manifest_name="libvgraph-interop-$version-assets.sha256"
package="$fixture/target/package/$package_name"
sbom="$fixture/target/release/$sbom_name"
evidence_bundle="$fixture/target/release/$evidence_name"
asset_manifest="$fixture/target/release/$manifest_name"
stage_name="libvgraph-interop-$version-evidence-$source_commit"
stage="$fixture/target/release/$stage_name"

write_internal_manifest() {
  local target_stage="$1"
  local temporary_manifest
  temporary_manifest="$(mktemp "$run_directory/SHA256SUMS.XXXXXXXX")"
  (
    cd "$target_stage"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 \
      | sort -z \
      | xargs -0 sha256sum
  ) > "$temporary_manifest"
  mv "$temporary_manifest" "$target_stage/SHA256SUMS"
}

printf '%s\n' 'deterministic package fixture' > "$package"
jq -n \
  --arg version "$version" \
  '{bomFormat: "CycloneDX", specVersion: "1.5",
    metadata: {component: {name: "libvgraph-interop", version: $version}}}' \
  > "$sbom"
mkdir "$stage"
while IFS= read -r evidence_file; do
  printf 'fixture evidence: %s\n' "$evidence_file" > "$stage/$evidence_file"
done < "$fixture/scripts/release-evidence-files.txt"
: > "$stage/mutation-missed.txt"
: > "$stage/mutation-timeout.txt"
cp "$fixture/formal/contract.sha256" "$stage/formal-contract.sha256"
cp "$fixture/formal/refinement.tsv" "$stage/formal-refinement.tsv"
cp "$fixture/docs/diagrams/rendered.sha256" "$stage/rendered-diagrams.sha256"
package_sha256="$(sha256sum "$package" | cut -d' ' -f1)"
sbom_sha256="$(sha256sum "$sbom" | cut -d' ' -f1)"
jq -n --arg version "$version" --arg checksum "$package_sha256" \
  '{version: {num: $version, checksum: $checksum}}' \
  > "$stage/crates-io-libvgraph-interop-$version.json"
jq -n \
  --arg version "$version" \
  --arg source_commit "$source_commit" \
  --arg formal_commit '59952b0cccbdd32f18f2c13f87c539c7e5427e5d' \
  --arg package_sha256 "$package_sha256" \
  --arg sbom_sha256 "$sbom_sha256" \
  '{schema: "libvgraph-interop-release-evidence-v1", crate_version: $version,
    source_commit: $source_commit, formal_commit: $formal_commit,
    package_sha256: $package_sha256, sbom_sha256: $sbom_sha256}' \
  > "$stage/evidence.json"
write_internal_manifest "$stage"
tar -cf "$evidence_bundle" -C "$fixture/target/release" "$stage_name"
for asset in "$package" "$sbom" "$evidence_bundle"; do
  printf '%s  %s\n' \
    "$(sha256sum "$asset" | cut -d' ' -f1)" "$(basename "$asset")"
done > "$asset_manifest"
stage_backup="$run_directory/good-stage"
cp -a "$stage" "$stage_backup"

gh() {
  local operation="${1:-}"
  if [[ "$operation" == api ]]; then
    shift
    local download=0
    if [[ "${1:-}" == -H ]]; then
      [[ "${2:-}" == 'Accept: application/octet-stream' ]] || return 64
      shift 2
      download=1
    fi
    local endpoint="${1:-}"
    if [[ "$download" -eq 1 ]]; then
      local asset_id="${endpoint##*/}"
      [[ "$asset_id" =~ ^[1-9][0-9]*$ ]] || return 64
      mapfile -t names < <(find "$FAKE_GH_ASSETS" -maxdepth 1 -type f -printf '%f\n' | sort)
      local index=$((asset_id - 1))
      [[ "$index" -lt "${#names[@]}" ]] || return 66
      command cat -- "$FAKE_GH_ASSETS/${names[$index]}"
      return
    fi
    [[ "$endpoint" == "repos/vinary-tree/libvgraph-interop/releases/$release_id" ]] \
      || return 64
    local assets
    assets="$(
      find "$FAKE_GH_ASSETS" -maxdepth 1 -type f -printf '%f\n' \
        | sort \
        | jq -Rn \
          '[inputs | select(length > 0)]
           | to_entries
           | map({id: (.key + 1), name: .value, state: "uploaded"})'
    )"
    if [[ "${FAKE_GH_DUPLICATE_NAME:-0}" == 1 && "$(jq 'length' <<<"$assets")" -gt 0 ]]; then
      assets="$(jq '. + [.[0]]' <<<"$assets")"
    fi
    if [[ -n "${FAKE_GH_ASSET_STATE:-}" && "$(jq 'length' <<<"$assets")" -gt 0 ]]; then
      assets="$(jq --arg state "$FAKE_GH_ASSET_STATE" '.[0].state = $state' <<<"$assets")"
    fi
    local draft=true
    local immutable=false
    if [[ "$FAKE_GH_RELEASE_STATE" == published ]]; then
      draft=false
      immutable="${FAKE_GH_IMMUTABLE:-true}"
    fi
    jq -n \
      --arg tag "$tag" \
      --argjson release_id "$release_id" \
      --argjson draft "$draft" \
      --argjson immutable "$immutable" \
      --argjson assets "$assets" \
      '{id: $release_id, tag_name: $tag, draft: $draft,
        immutable: $immutable, assets: $assets}'
    return
  fi
  if [[ "$operation" == release && "${2:-}" == upload ]]; then
    local upload_tag="${3:-}"
    local upload_path="${4:-}"
    [[ "$upload_tag" == "$tag" && "${5:-}" == --repo \
      && "${6:-}" == vinary-tree/libvgraph-interop ]] || return 64
    local upload_name
    upload_name="$(basename "$upload_path")"
    [[ ! -e "$FAKE_GH_ASSETS/$upload_name" ]] || return 65
    cp "$upload_path" "$FAKE_GH_ASSETS/$upload_name"
    printf '%s\n' "$upload_name" >> "$FAKE_GH_UPLOAD_LOG"
    return
  fi
  return 64
}
export -f gh
export FAKE_GH_ASSETS="$remote_assets"
export FAKE_GH_UPLOAD_LOG="$upload_log"
export FAKE_GH_RELEASE_STATE=draft

run_reconcile() {
  local state="$1"
  GITHUB_REPOSITORY=vinary-tree/libvgraph-interop \
    "$fixture/scripts/reconcile-release-assets.sh" \
      "$version" "$tag" "$release_id" "$state"
}

expect_rejected() {
  local label="$1"
  shift
  if "$@" > "$run_directory/$label.log" 2>&1; then
    printf 'release reconciliation case unexpectedly passed: %s\n' "$label" >&2
    exit 1
  fi
}

run_reconcile draft > "$run_directory/draft.log"
if [[ "$(find "$remote_assets" -maxdepth 1 -type f | wc -l)" -ne 4 \
    || "$(wc -l < "$upload_log")" -ne 4 ]]; then
  printf '%s\n' 'draft reconciliation did not upload exactly four assets once' >&2
  exit 1
fi
run_reconcile draft > "$run_directory/retry.log"
if [[ "$(wc -l < "$upload_log")" -ne 4 ]]; then
  printf '%s\n' 'draft retry uploaded an already-present asset' >&2
  exit 1
fi
cp -a "$remote_assets" "$good_remote_assets"
export FAKE_GH_RELEASE_STATE=published
run_reconcile published > "$run_directory/published.log"

reset_remote() {
  rm -rf -- "$remote_assets"
  cp -a "$good_remote_assets" "$remote_assets"
  export FAKE_GH_RELEASE_STATE=draft
  unset FAKE_GH_DUPLICATE_NAME FAKE_GH_ASSET_STATE FAKE_GH_IMMUTABLE
}

reset_remote
printf '%s\n' tampered > "$remote_assets/$package_name"
expect_rejected mismatched-package run_reconcile draft

reset_remote
printf '%s\n' unexpected > "$remote_assets/unexpected.bin"
expect_rejected unexpected-asset run_reconcile draft

reset_remote
export FAKE_GH_DUPLICATE_NAME=1
expect_rejected duplicate-name run_reconcile draft

reset_remote
export FAKE_GH_ASSET_STATE=new
expect_rejected non-uploaded-state run_reconcile draft

reset_remote
export FAKE_GH_RELEASE_STATE=published
export FAKE_GH_IMMUTABLE=false
expect_rejected mutable-published-release run_reconcile published

reset_remote
export FAKE_GH_RELEASE_STATE=published
rm -- "$remote_assets/$manifest_name"
expect_rejected incomplete-published-release run_reconcile published

reset_remote
rm -rf -- "$stage"
mkdir "$stage"
cp "$stage_backup/evidence.json" "$stage/evidence.json"
(
  cd "$stage"
  sha256sum ./evidence.json > SHA256SUMS
)
tar -cf "$remote_assets/$evidence_name" -C "$fixture/target/release" "$stage_name"
expect_rejected incomplete-evidence run_reconcile draft

reset_remote
rm -rf -- "$stage"
cp -a "$stage_backup" "$stage"
ln -s evidence.json "$stage/rogue-link"
tar -cf "$remote_assets/$evidence_name" -C "$fixture/target/release" "$stage_name"
expect_rejected symlink-evidence run_reconcile draft

reset_remote
rm -rf -- "$stage"
cp -a "$stage_backup" "$stage"
printf '%s\n' altered > "$stage/formal-contract.sha256"
write_internal_manifest "$stage"
tar -cf "$remote_assets/$evidence_name" -C "$fixture/target/release" "$stage_name"
expect_rejected changed-formal-binding run_reconcile draft

reset_remote
rm -rf -- "$stage"
cp -a "$stage_backup" "$stage"
jq '.version.checksum = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
  "$stage/crates-io-libvgraph-interop-$version.json" \
  > "$stage/registry.tmp"
mv "$stage/registry.tmp" "$stage/crates-io-libvgraph-interop-$version.json"
write_internal_manifest "$stage"
tar -cf "$remote_assets/$evidence_name" -C "$fixture/target/release" "$stage_name"
expect_rejected changed-registry-binding run_reconcile draft

expect_rejected invalid-version env GITHUB_REPOSITORY=vinary-tree/libvgraph-interop \
  "$fixture/scripts/reconcile-release-assets.sh" \
  01.0.0 v01.0.0 "$release_id" draft

printf '%s\n' \
  'verified draft upload, retry convergence, published validation, and eleven adversarial release-asset cases'
