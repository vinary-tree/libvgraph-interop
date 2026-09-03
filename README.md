# libvgraph-interop

`libvgraph-interop` is the versioned, formally specified interchange boundary for
[`libvgraph`](https://github.com/vinary-tree/libvgraph). It encodes canonical forward
compressed sparse row (CSR) graphs into one exact binary schema and binds those bytes to an
opaque semantic profile with a domain-separated BLAKE3 digest.

The crate is deliberately narrow. It does not serialize stable labels, reverse adjacency,
code-property-graph facts, parser state, equality graphs, or provenance. Those values remain in
domain adapters, while `libvgraph` remains free of serialization and hashing dependencies.

## Guarantees

- Exact 80-byte, little-endian version 1.0 header and canonical forward-CSR payload.
- Strict schema, version, flags, semantic-profile, length, limit, and CSR admission.
- Checked length arithmetic and fallible minimum-capacity reservations before publication.
- Deterministic linear work with graph-depth-independent native stack use.
- Optional deterministic work limits, byte-progress cancellation thresholds, and cooperative
  atomic cancellation.
- BLAKE3 derive-key domain separation over schema, profile, byte length, and complete bytes.
- Full 32-byte digest comparison through BLAKE3's constant-time `Hash` equality.
- No global mutable codec state; independent requests may run concurrently.

## Example

```rust
use libvgraph::{BuildOptions, CsrGraph, DenseId, ReversePolicy};
use libvgraph_interop::{
    decode_verified_snapshot, digest_snapshot, encode_snapshot, SemanticProfileId,
    SnapshotLimits,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let graph = CsrGraph::from_dense_edges_with_options(
        3,
        [
            (DenseId::from_raw(0), DenseId::from_raw(1)),
            (DenseId::from_raw(1), DenseId::from_raw(2)),
        ],
        BuildOptions {
            reverse: ReversePolicy::Omit,
            ..BuildOptions::default()
        },
    )?;
    let profile = SemanticProfileId::new([7; 32]);
    let bytes = encode_snapshot(&graph, profile)?;
    let digest = digest_snapshot(&bytes, profile);
    let decoded = decode_verified_snapshot(
        &bytes,
        profile,
        digest,
        SnapshotLimits {
            max_vertices: 1_000_000,
            max_edges: 8_000_000,
            max_bytes: 64 * 1024 * 1024,
        },
    )?;
    assert_eq!(decoded, graph);
    Ok(())
}
```

## Start here

- [Architecture and ownership](docs/architecture/boundary.md)
- [Literate algorithms](docs/architecture/algorithms.md)
- [Normative wire format](docs/usage/wire-format.md)
- [Rust API guide](docs/usage/rust-api.md)
- [Canonical snapshot laws](docs/theory/canonical-laws.md)
- [Verification method](docs/science/verification.md)
- [Performance and concurrency](docs/engineering/performance-and-concurrency.md)
- [Security and resource safety](docs/security/resource-safety.md)
- [Formal provenance](formal/README.md)
- [Immutable release process](docs/releases/process.md)
- [Diagram catalog](docs/diagrams/README.md)
- [Glossary and notation](docs/glossary.md)
- [Contribution and verification policy](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Release history](CHANGELOG.md)
- [Version 0.1.0 release record](docs/releases/v0.1.0.md)

## Verification

Run `scripts/verify.sh` from a checkout whose sibling formal source is the exact
`libvgraph` commit named by `formal/source.commit`; `formal/contract.sha256` binds its proof
artifacts. Every heavy command is placed
inside an explicit no-swap `systemd-run` scope and writes evidence under `target/verification`.
Documentation verification is read-only: it never invokes vinary-doc-lint auto-repair.

## License

Apache-2.0. See [LICENSE](./LICENSE).
