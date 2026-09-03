#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
evidence_directory="$repository_root/target/verification"
repository_tmp="$repository_root/target/tmp"
mkdir -p "$evidence_directory" "$repository_tmp"
cd "$repository_root"

run_gate() {
  local name="$1"
  shift
  printf '==> %s\n' "$name"
  "$@" >"$evidence_directory/$name.log" 2>&1
}

verify_clean_source() {
  local dirty_state
  dirty_state="$(git status --porcelain --untracked-files=all)"
  if [[ -n "$dirty_state" ]]; then
    printf '%s\n' 'portable release evidence requires a clean source commit' >&2
    printf '%s\n' "$dirty_state" >&2
    return 1
  fi
}

verify_clean_source

run_gate portable-tool-bootstrap "$repository_root/scripts/check-portable-tools.sh" bootstrap
run_gate formal-source-workflows "$repository_root/scripts/check-formal-source-workflows.sh"
run_gate formal-provenance "$repository_root/scripts/verify-formal-provenance.sh"
run_gate refinement "$repository_root/scripts/check-refinement.sh"
run_gate provision-tools "$repository_root/scripts/provision-verification-tools.sh"
run_gate portable-tool-closure "$repository_root/scripts/check-portable-tools.sh" complete
shell_sources=(
  "$repository_root/scripts/plantuml"
  "$repository_root"/scripts/*.sh
  "$repository_root"/scripts/fixtures/*.sh
)
run_gate shellcheck "$repository_root/target/verification-tools/shellcheck" \
  -x "${shell_sources[@]}"
run_gate yamllint yamllint --strict --config-file "$repository_root/.yamllint.yml" \
  "$repository_root/.github/workflows" "$repository_root/.yamllint.yml"
run_gate cargo-fmt cargo fmt --all -- --check
run_gate fuzz-fmt cargo +nightly-2026-04-21 fmt \
  --manifest-path "$repository_root/fuzz/Cargo.toml" -- --check
run_gate cargo-check cargo check --locked --all-targets
run_gate cargo-clippy cargo clippy --locked --all-targets -- -D warnings
run_gate cargo-test env PROPTEST_CASES=256 cargo test --locked --all-targets
run_gate cargo-doctest cargo test --locked --doc
run_gate cargo-doc env RUSTDOCFLAGS=-Dwarnings cargo doc --locked --no-deps
run_gate cargo-deny cargo deny check --hide-inclusion-graph
run_gate release-workflow "$repository_root/scripts/check-release-workflow.sh"
run_gate release-workflow-properties "$repository_root/scripts/test-release-workflow.sh"
run_gate release-assets-properties "$repository_root/scripts/test-reconcile-release-assets.sh"
run_gate registry-release-properties "$repository_root/scripts/test-registry-release-status.sh"
run_gate release-sbom-properties "$repository_root/scripts/test-release-sbom.sh"
run_gate release-version-properties "$repository_root/scripts/test-release-version.sh"
run_gate portable-tool-properties "$repository_root/scripts/test-portable-tools.sh"
run_gate formal-source-binding-properties \
  "$repository_root/scripts/test-formal-source-binding.sh"
run_gate actionlint "$repository_root/target/verification-tools/actionlint"
run_gate docs "$repository_root/scripts/verify-docs.sh"
run_gate package-inventory "$repository_root/scripts/check-package.sh"
run_gate cargo-package cargo package --locked
run_gate source-clean verify_clean_source

printf '%s\n' 'all portable libvgraph-interop verification gates passed'
