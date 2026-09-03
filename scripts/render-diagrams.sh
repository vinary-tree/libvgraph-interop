#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository_tmp="$repository_root/target/tmp"
render_mode="${1:---check}"
diagram_names=(
  boundary-components
  admission-machine
  canonical-round-trip
  release-machine
  wire-layout
)
mkdir -p "$repository_tmp"

if [[ "$render_mode" != --check && "$render_mode" != --write ]]; then
  printf 'usage: %s [--check|--write]\n' "$0" >&2
  exit 2
fi

if [[ "${LIBVGRAPH_INTEROP_DOCS_SCOPED:-0}" != 1 ]]; then
  exec systemd-run --user --scope \
    -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=100% -p TasksMax=64 \
    env LIBVGRAPH_INTEROP_DOCS_SCOPED=1 TMPDIR="$repository_tmp" \
    JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.io.tmpdir=$repository_tmp" \
    "$repository_root/scripts/render-diagrams.sh" "$render_mode"
fi

"$repository_root/scripts/provision-verification-tools.sh"
if [[ "$render_mode" == --write ]]; then
  diagram_sources=()
  for diagram_name in "${diagram_names[@]}"; do
    diagram_sources+=("$repository_root/docs/diagrams/$diagram_name.puml")
  done
  "$repository_root/scripts/plantuml" -tsvg "${diagram_sources[@]}"
  printf '%s\n' 'rendered checked-in diagrams; inspect them and update rendered.sha256 explicitly'
  exit 0
fi

staging_directory="$(mktemp -d "$repository_tmp/diagram-check.XXXXXX")"
cleanup() {
  rm -rf -- "$staging_directory"
}
trap cleanup EXIT
for diagram_name in "${diagram_names[@]}"; do
  cp "$repository_root/docs/diagrams/$diagram_name.puml" "$staging_directory/"
done
"$repository_root/scripts/plantuml" -tsvg "$staging_directory"/*.puml
for diagram_name in "${diagram_names[@]}"; do
  if ! cmp --silent \
      "$staging_directory/$diagram_name.svg" \
      "$repository_root/docs/diagrams/$diagram_name.svg"; then
    printf 'diagram rendering differs from checked-in artifact: %s.svg\n' \
      "$diagram_name" >&2
    exit 1
  fi
done
printf 'verified %s deterministic diagram renderings without modifying sources\n' \
  "${#diagram_names[@]}"
