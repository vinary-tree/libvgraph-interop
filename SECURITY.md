# Security policy

## Supported releases

| Release line | Security support |
|---|---|
| Published 0.1.x versions | Supported |
| Unreleased branches | Not a security boundary |

Report a vulnerability privately through
[GitHub private vulnerability reporting](https://github.com/vinary-tree/libvgraph-interop/security/advisories/new).
Include the affected version, input or call sequence, observed impact, expected invariant, and a
minimal reproducer when disclosure is safe. Do not open a public issue before coordinated
disclosure. Never include credentials, private payloads, or production semantic-profile material.

## Security boundary

Snapshot bytes are untrusted until every configured limit, fixed header, schema, exact version,
flags word, semantic profile, length equation, canonical CSR invariant, optional expected digest,
and final cancellation observation succeeds. A rejection returns no graph. Callers must configure
finite limits at every untrusted boundary; `SnapshotLimits::unbounded()` is appropriate only when
another layer already proves an equal or tighter bound.

The digest detects stale or substituted bytes only when the expected digest arrives through an
authenticated channel or signed manifest. It is not a message authentication code or signature.
An attacker who controls both values can replace both. The semantic profile separates
interpretations but is not a credential or authorization token. Neither snapshots nor digests
provide confidentiality; encrypt sensitive snapshots in the owning transport or storage layer.

`SnapshotDigest` equality delegates to BLAKE3's constant-time 32-byte hash comparison. The rest of
admission and its typed error selection are intentionally not constant-time. Structural errors
report bounded fields and positions but never echo a complete hostile payload. The codec uses no
unsafe Rust, native recursion, ambient cache, global lock, or mutable singleton.

## Resource and denial-of-service considerations

The complete byte limit is checked before verified hashing or header access. Count-derived lengths
and structural work are checked before allocation. Minimum-capacity reservations are fallible.
Parsing, validation, digesting, unwinding, and destruction use graph-depth-independent native stack.
Cancellation is cooperative, so a caller must combine it with finite byte, vertex, edge, and work
limits suitable for its service-level objective.

The precise threat model, failure equation, and residual boundaries are in
[resource safety](docs/security/resource-safety.md). Release acceptance includes arbitrary-byte
fuzzing, mutation testing with no unproved survivors, malformed-class tests, and a 100,000-vertex
lifecycle on a 64 KiB thread stack.

## Response process

Maintainers acknowledge a complete report privately, reproduce it against a supported release,
classify the violated invariant, and develop the formal counterexample or proof obligation before
the production patch. A security release receives a new immutable version and tag; published crate
versions and existing wire meanings are never overwritten.
