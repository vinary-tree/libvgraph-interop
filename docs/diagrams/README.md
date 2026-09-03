# Diagram catalog

PlantUML sources and byte-reproducible SVG renderings are kept together.

| Diagram | Source | Purpose |
|---|---|---|
| [Boundary components](boundary-components.svg) | [PlantUML](boundary-components.puml) | Dependency and ownership separation |
| [Admission machine](admission-machine.svg) | [PlantUML](admission-machine.puml) | Fail-closed decode and verified-decode stages |
| [Wire layout](wire-layout.svg) | [PlantUML](wire-layout.puml) | Exact version 1.0 header and payload arrangement |
| [Canonical round trip](canonical-round-trip.svg) | [PlantUML](canonical-round-trip.puml) | Left-inverse law in the category **Set** |
| [Release machine](release-machine.svg) | [PlantUML](release-machine.puml) | Fail-closed registry and immutable-publication lifecycle |

Run `scripts/render-diagrams.sh --write` in headless mode after changing a `.puml` source. The
script uses
the checksum-pinned PlantUML 1.2026.5 release and its internal Smetana layout engine, avoiding
host-Graphviz layout drift. After visually inspecting every changed SVG, update
`rendered.sha256`. The documentation gate renders into repository-backed temporary storage,
byte-compares each result with its checked-in SVG without modifying documentation, verifies the
checksums, and then runs the checksum-pinned vinary-doc-lint 0.1.1 binary without automatic repair.
Diagram compilation stays in the pinned render gate because vinary-doc-lint 0.1.1's independent
PlantUML reproducibility adapter has a tracked false-positive defect.
