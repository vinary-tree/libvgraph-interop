#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repository_root/scripts/check-portable-tools.sh"
test_root="$repository_root/target/portable-tool-tests"
mkdir -p "$test_root"
run_directory="$(mktemp -d "$test_root/run.XXXXXXXX")"
trap 'rm -rf -- "$run_directory"' EXIT

# shellcheck source=scripts/check-portable-tools.sh
source "$checker"

portable_tool_is_declared() {
  local expected="$1"
  shift
  local candidate
  local matches=0
  for candidate in "$@"; do
    if [[ "$candidate" == "$expected" ]]; then
      matches="$((matches + 1))"
    fi
  done
  [[ "$matches" -eq 1 ]]
}

diagram_font_is_explicit() {
  local source="$1"
  [[ -f "$source" && ! -L "$source" ]] \
    && [[ "$(grep -F -x -c -- 'skinparam defaultFontName DejaVu Sans' \
      "$source" || true)" -eq 1 ]]
}

portable_gates_check_clean_source() {
  local verifier="$1"
  local expected="  verify_clean_source >>\"\$evidence_directory/\$name.log\" 2>&1"
  [[ -f "$verifier" && ! -L "$verifier" ]] \
    && [[ "$(grep -F -x -c -- "$expected" "$verifier" || true)" -eq 1 ]]
}

portable_tool_closure_is_explicit bash grep
if portable_tool_closure_is_explicit __libvgraph_missing_command__ \
    > "$run_directory/missing.log" 2>&1; then
  printf '%s\n' 'portable tool closure admitted a missing command' >&2
  exit 1
fi

"$checker" bootstrap > "$run_directory/bootstrap.log"
"$checker" complete > "$run_directory/complete.log"
for diagram_source in "$repository_root"/docs/diagrams/*.puml; do
  if ! diagram_font_is_explicit "$diagram_source"; then
    printf 'PlantUML source does not select the deterministic font exactly once: %s\n' \
      "$diagram_source" >&2
    exit 1
  fi
  font_mutant="$run_directory/${diagram_source##*/}"
  cp "$diagram_source" "$font_mutant"
  SEARCH='skinparam defaultFontName DejaVu Sans' REPLACEMENT='' perl -0pi -e \
    's/\Q$ENV{SEARCH}\E/$ENV{REPLACEMENT}/' "$font_mutant"
  if diagram_font_is_explicit "$font_mutant"; then
    printf 'implicit-font diagram mutant unexpectedly passed: %s\n' \
      "$diagram_source" >&2
    exit 1
  fi
done
if ! plantuml_layout_is_internal "$repository_root/scripts/plantuml"; then
  printf '%s\n' 'PlantUML wrapper does not select the pinned internal Smetana layout' >&2
  exit 1
fi
diagram_source="$run_directory/ambient-graphviz.puml"
cp "$repository_root/docs/diagrams/release-machine.puml" "$diagram_source"
if ! GRAPHVIZ_DOT=/opt/local/bin/dot \
    "$repository_root/scripts/plantuml" -tsvg "$diagram_source" \
    > "$run_directory/ambient-graphviz.log" 2>&1; then
  printf '%s\n' 'PlantUML wrapper trusted a poisoned ambient Graphviz path' >&2
  exit 1
fi

plantuml_mutant_root="$run_directory/plantuml-mutant-root"
mkdir -p "$plantuml_mutant_root/scripts"
cp "$repository_root/scripts/plantuml" "$plantuml_mutant_root/scripts/plantuml"
ln -s "$repository_root/target" "$plantuml_mutant_root/target"
SEARCH=' -Playout=smetana' REPLACEMENT='' perl -0pi -e \
  's/\Q$ENV{SEARCH}\E/$ENV{REPLACEMENT}/' \
  "$plantuml_mutant_root/scripts/plantuml"
if plantuml_layout_is_internal "$plantuml_mutant_root/scripts/plantuml" \
    > "$run_directory/external-graphviz-mutant.log" 2>&1; then
  printf '%s\n' 'external-Graphviz PlantUML mutant unexpectedly passed' >&2
  exit 1
fi
if ! portable_tool_is_declared cat "${complete_tools[@]}"; then
  printf '%s\n' 'PlantUML renderer dependency is not declared exactly once: cat' >&2
  exit 1
fi
if portable_tool_is_declared dot "${complete_tools[@]}"; then
  printf '%s\n' 'portable PlantUML unexpectedly declares external Graphviz' >&2
  exit 1
fi

portable_verifier_mutant="$run_directory/verify-portable.sh"
cp "$repository_root/scripts/verify-portable.sh" "$portable_verifier_mutant"
if ! portable_gates_check_clean_source "$repository_root/scripts/verify-portable.sh"; then
  printf '%s\n' 'portable verifier does not check source cleanliness after every gate' >&2
  exit 1
fi
SEARCH="  verify_clean_source >>\"\$evidence_directory/\$name.log\" 2>&1" \
REPLACEMENT='' perl -0pi -e \
  's/\Q$ENV{SEARCH}\E/$ENV{REPLACEMENT}/' "$portable_verifier_mutant"
if portable_gates_check_clean_source "$portable_verifier_mutant"; then
  printf '%s\n' 'missing per-gate source-cleanliness mutant unexpectedly passed' >&2
  exit 1
fi
cp "$repository_root/scripts/verify-portable.sh" "$portable_verifier_mutant"
SEARCH=' -shellcheck=' REPLACEMENT='' perl -0pi -e \
  's/\Q$ENV{SEARCH}\E/$ENV{REPLACEMENT}/' "$portable_verifier_mutant"
if actionlint_is_isolated_from_system_shellcheck "$portable_verifier_mutant" \
    > "$run_directory/actionlint-system-shellcheck.log" 2>&1; then
  printf '%s\n' 'actionlint system-ShellCheck discovery mutant unexpectedly passed' >&2
  exit 1
fi
if "$checker" unknown > "$run_directory/unknown.log" 2>&1; then
  printf '%s\n' 'portable tool closure admitted an unknown phase' >&2
  exit 1
fi

nonportable_tool='r''g'
if grep -R -E -n \
    "(^|[[:space:]])${nonportable_tool}([[:space:]]|$)" \
    "$repository_root/scripts" "$repository_root/.github/workflows" \
    > "$run_directory/nonportable.log"; then
  printf 'undeclared nonportable command remains:\n%s\n' \
    "$(<"$run_directory/nonportable.log")" >&2
  exit 1
fi

printf '%s\n' \
  'verified declared command closure, isolated renderer paths, isolated actionlint, missing-command rejection, and no ripgrep dependency'
