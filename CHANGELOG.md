# Changelog

Every notable change to `libvgraph-interop` is recorded here. The project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html), and this file follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- Exact version 1.0 canonical forward-CSR snapshot encoding and fail-closed decoding.
- Opaque 256-bit semantic-profile identities and domain-separated BLAKE3 snapshot digests.
- Byte, vertex, edge, and deterministic structural-work admission limits.
- Cooperative atomic cancellation with bounded observations during long flat scans.
- Typed errors for compatibility, length, allocation, canonicality, resource, cancellation, and
  digest failures.
- Immutable formal provenance with 74 executable refinement mappings.
- Property, exhaustive, malformed-input, golden-vector, concurrency, stack-safety, fuzz, mutation,
  benchmark, documentation, and package verification infrastructure.
- Exact runtime and development dependency pins for reproducible immutable release verification.
