#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
evidence_directory="$repository_root/target/verification"
inventory="$evidence_directory/package-files.txt"
mkdir -p "$evidence_directory"
cd "$repository_root"

cargo package --locked --list > "$inventory"
required_files=(
  .github/allowed_signers
  .github/workflows/ci.yml
  .github/workflows/release.yml
  .vinary-doc-lint.toml
  .yamllint.yml
  Cargo.lock
  Cargo.toml
  CONTRIBUTING.md
  README.md
  SECURITY.md
  deny.toml
  docs/releases/v0.1.0.md
  formal/contract.sha256
  formal/refinement.tsv
  scripts/check-package.sh
  scripts/check-refinement.sh
  scripts/check-release-workflow.sh
  scripts/build-release-evidence.sh
  scripts/generate-release-sbom.sh
  scripts/reconcile-release-assets.sh
  scripts/release-evidence-files.txt
  scripts/registry-release-status.sh
  scripts/run-benchmark.sh
  scripts/run-fuzz.sh
  scripts/run-mutation.sh
  scripts/test-release-workflow.sh
  scripts/test-reconcile-release-assets.sh
  scripts/test-release-sbom.sh
  scripts/test-release-version.sh
  scripts/validate-release-version.sh
  scripts/verify-formal-provenance.sh
  scripts/verify-portable.sh
  scripts/verify-release-candidate.sh
  scripts/verify.sh
)

for required_file in "${required_files[@]}"; do
  if ! rg -F -x -q -- "$required_file" "$inventory"; then
    printf 'publish archive inventory omits required file: %s\n' "$required_file" >&2
    exit 1
  fi
done
if rg -q '(^|/)(target|\.git)(/|$)' "$inventory"; then
  printf '%s\n' 'publish archive inventory contains generated or Git state' >&2
  exit 1
fi

printf 'verified publish archive inventory with %s files\n' "$(wc -l < "$inventory")"
