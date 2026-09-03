# Contributing to libvgraph-interop

Contributions must preserve the crate's narrow ownership boundary, exact byte compatibility, and
formal-first assurance. Read the [architecture](docs/architecture/boundary.md),
[wire format](docs/usage/wire-format.md), and [verification method](docs/science/verification.md)
before changing behavior.

## Boundary rules

`libvgraph-interop` may depend on `libvgraph`; `libvgraph` must never depend on this crate. Keep
stable-label codecs, provenance, code-property-graph facts, parser policy, equality saturation,
executors, and domain payloads in their owning adapters. Hashing and serialization must remain
outside graph-analysis hot loops.

Any change to field width, field order, schema identity, version acceptance, canonicality,
semantic-profile meaning, digest context, or digest key material changes the persistent protocol.
Such a change requires a new schema identity, a decoder for every retained schema, explicit
migration through a validated graph, new literal vectors, and formal evidence before Rust code.

## Formal-first sequence

1. State the proposed semantic and resource invariants in the `libvgraph` formal branch.
2. Prove or model-check the new obligations and add causal mutants for security-critical gates.
3. Freeze exact formal artifact hashes at an immutable commit.
4. Add each invariant to `formal/refinement.tsv` with its production symbol and acceptance test.
5. Implement the smallest general production refinement with flat, bounded, iterative control.
6. Add property and exhaustive tests derived from every changed invariant.
7. Run the complete acceptance sequence before requesting review.

Native call depth must remain independent of graph depth. Lengths, capacities, and work counts use
checked arithmetic. Untrusted-input allocation is fallible and occurs only after admission. Do not
introduce recursive graph processing, unbounded normalization, silent repair, global mutable
state, or an error path that can publish a partial graph.

## Local verification

The minimum supported Rust version is 1.85. Heavy commands must use repository-backed temporary
storage and the checked-in resource wrappers; this host's `/tmp` is memory-backed. Run:

```bash
scripts/verify.sh
```

`scripts/verify.sh` performs formal provenance and refinement gates first, then format, build,
Clippy, tests, rustdoc, dependency policy, release-workflow properties, package, documentation,
fuzz, mutation, benchmark, and pgmcp bug gates. It limits the process tree to 4 GiB resident
memory, disables swap, caps work to one CPU, and limits Cargo to one build job. The fuzz wrapper
uses the explicitly selected `nightly-2026-04-21` toolchain required by sanitizer instrumentation;
the library and all release gates remain on the declared Rust 1.85 minimum.

Run `scripts/run-benchmark.sh` only from a clean commit. It records the source, toolchain, CPU,
affinity, governor, resource scope, and Criterion results. Do not repeat unrelated graph-algorithm
comparisons when the change affects only the codec.

## Documentation

Documentation changes follow pgmcp's documentation guidelines. Use GFM MathJax delimiters, define
terms before use, retain editable PlantUML sources beside generated SVG files, and cite primary
sources. `scripts/verify-docs.sh` provisions checksum-pinned tools, renders headlessly, checks the
render manifest, and invokes vinary-doc-lint in read-only mode. Never apply its automatic repairs;
inspect every diagnostic and edit the source deliberately. Record confirmed linter defects in
pgmcp.

## Review and commits

Keep commits cohesive and include the relevant pgmcp work-item identifier. Reviewers must be able
to trace every semantic change from formal invariant to production symbol to acceptance evidence.
No release may proceed with an unproved mutation survivor, fuzz crash, warning, malformed-input
gap, documentation diagnostic, mutable dependency revision, or uncommitted source change.
