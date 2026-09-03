# Rust API guide

The public application programming interface (API) separates structural admission, integrity
checking, resource limits, and cooperative control. These examples target `libvgraph` 0.1.0 and
`libvgraph-interop` 0.1.0 and are compiled by the documentation test gate.

## Install exact interoperable versions

Persisted bytes are a compatibility boundary, so applications should select exact crate versions
and commit `Cargo.lock`:

```toml
[dependencies]
libvgraph = "=0.1.0"
libvgraph-interop = "=0.1.0"
```

## Construct a semantic profile

`SemanticProfileId` is deliberately opaque. A domain adapter should derive its 32 bytes from a
versioned semantic manifest containing every fact that changes dense-graph interpretation. This
crate compares the bytes but does not prescribe that manifest.

```rust
use libvgraph_interop::SemanticProfileId;

fn main() {
    let profile = SemanticProfileId::new([0x42; 32]);
    assert_eq!(profile.as_bytes(), &[0x42; 32]);
}
```

Do not use a profile as authentication. Its purpose is semantic separation.

## Encode and digest

```rust
use libvgraph::{BuildOptions, CsrGraph, DenseId, ReversePolicy};
use libvgraph_interop::{digest_snapshot, encode_snapshot, SemanticProfileId};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let graph = CsrGraph::from_dense_edges_with_options(
        2,
        [(DenseId::from_raw(0), DenseId::from_raw(1))],
        BuildOptions {
            reverse: ReversePolicy::Omit,
            ..BuildOptions::default()
        },
    )?;
    let profile = SemanticProfileId::new([3; 32]);
    let bytes = encode_snapshot(&graph, profile)?;
    let digest = digest_snapshot(&bytes, profile);
    assert_eq!(digest.as_bytes().len(), 32);
    Ok(())
}
```

The encoder emits canonical forward compressed sparse row (CSR) data even when the source graph
also materializes reverse CSR.

## Decode untrusted bytes

Always choose limits at the application trust boundary. This complete example first creates valid
bytes so successful admission, rather than an unspecified failure, is observable:

```rust
use libvgraph::{BuildOptions, CsrGraph, DenseId, ReversePolicy};
use libvgraph_interop::{
    decode_snapshot, encode_snapshot, SemanticProfileId, SnapshotLimits,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let graph = CsrGraph::from_dense_edges_with_options(
        2,
        [(DenseId::from_raw(0), DenseId::from_raw(1))],
        BuildOptions {
            reverse: ReversePolicy::Omit,
            ..BuildOptions::default()
        },
    )?;
    let profile = SemanticProfileId::new([3; 32]);
    let bytes = encode_snapshot(&graph, profile)?;
    let limits = SnapshotLimits {
        max_vertices: 2,
        max_edges: 1,
        max_bytes: u64::try_from(bytes.len())?,
    };
    let decoded = decode_snapshot(&bytes, profile, limits)?;
    assert_eq!(decoded, graph);
    Ok(())
}
```

Decoded snapshots contain canonical forward CSR and omit reverse adjacency. A caller that needs a
reverse index must materialize it explicitly after admission. `SnapshotLimits::unbounded()` means
representation-wide limits and is suitable only when another layer already bounds the slice.

## Verify integrity

Use `decode_verified_snapshot` when an expected digest comes from a trusted cache index,
authenticated message, or signed manifest. The function rejects stale bytes before allocating a
graph.

```rust
use libvgraph::{BuildOptions, CsrGraph, DenseId, ReversePolicy};
use libvgraph_interop::{
    decode_verified_snapshot, digest_snapshot, encode_snapshot, SemanticProfileId, SnapshotError,
    SnapshotLimits,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let graph = CsrGraph::from_dense_edges_with_options(
        2,
        [(DenseId::from_raw(0), DenseId::from_raw(1))],
        BuildOptions {
            reverse: ReversePolicy::Omit,
            ..BuildOptions::default()
        },
    )?;
    let profile = SemanticProfileId::new([3; 32]);
    let mut bytes = encode_snapshot(&graph, profile)?;
    let expected = digest_snapshot(&bytes, profile);
    let decoded = decode_verified_snapshot(
        &bytes,
        profile,
        expected,
        SnapshotLimits::unbounded(),
    )?;
    assert_eq!(decoded, graph);

    bytes[0] ^= 1;
    assert!(matches!(
        decode_verified_snapshot(
            &bytes,
            profile,
            expected,
            SnapshotLimits::unbounded(),
        ),
        Err(SnapshotError::DigestMismatch { .. })
    ));
    Ok(())
}
```

The digest detects accidental or adversarial substitution only if the expected value is itself
protected. It is not a signature or message authentication code.

## Bound work and cancel

The work bound is deterministic from admitted counts. A budget equal to the bound succeeds; a
budget one unit lower returns the precise work-limit error before allocation. A caller-owned
atomic flag is a separate cooperative cancellation source.

```rust
use std::sync::atomic::{AtomicBool, Ordering};

use libvgraph::{BuildOptions, CsrGraph, DenseId, ReversePolicy};
use libvgraph_interop::{
    decode_snapshot_with_control, encode_snapshot, required_decode_work, DecodeControl,
    SemanticProfileId, SnapshotError, SnapshotLimits,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let graph = CsrGraph::from_dense_edges_with_options(
        2,
        [(DenseId::from_raw(0), DenseId::from_raw(1))],
        BuildOptions {
            reverse: ReversePolicy::Omit,
            ..BuildOptions::default()
        },
    )?;
    let profile = SemanticProfileId::new([3; 32]);
    let bytes = encode_snapshot(&graph, profile)?;
    let required = required_decode_work(2, 1)?;
    let admitted = decode_snapshot_with_control(
        &bytes,
        profile,
        SnapshotLimits::unbounded(),
        DecodeControl::with_work_limit(required),
    )?;
    assert_eq!(admitted, graph);

    assert_eq!(
        decode_snapshot_with_control(
            &bytes,
            profile,
            SnapshotLimits::unbounded(),
            DecodeControl::with_work_limit(required - 1),
        ),
        Err(SnapshotError::WorkLimitExceeded {
            limit: required - 1,
            required,
        })
    );

    let cancelled = AtomicBool::new(false);
    cancelled.store(true, Ordering::Relaxed);
    assert!(matches!(
        decode_snapshot_with_control(
            &bytes,
            profile,
            SnapshotLimits::unbounded(),
            DecodeControl::unlimited().with_cancellation(&cancelled),
        ),
        Err(SnapshotError::Cancelled { completed_bytes: 0 })
    ));
    Ok(())
}
```

Logical structural work excludes digest compression; `SnapshotLimits::max_bytes` bounds verified
decoder hashing before it begins. The atomic flag carries cancellation only; a relaxed observation
does not synchronize other caller data. Once a caller raises the flag, it must remain raised until
the call returns. A transient pulse that the decoder never observes is outside the cooperative
cancellation contract.

The deterministic byte threshold cancels when a digest or structural scan first reports progress
at or beyond it. Verified decoding applies the threshold independently to those two phases.
Cancellation is checked during long flat wire scans and at phase and publication boundaries. The
single `libvgraph` canonical-import scan is linear and stack-safe but does not accept a cancellation
callback; its completion is the maximum uninterruptible interval.

## Entry points and errors

| Entry point | Success | Distinguishing failure behavior |
|---|---|---|
| `snapshot_wire_len` | Exact version-1 byte length | `ArithmeticOverflow` |
| `required_decode_work` | Conservative complete structural-work bound | `ArithmeticOverflow` |
| `encode_snapshot` | Canonical version-1 bytes | `ArithmeticOverflow`, `AllocationFailed` |
| `digest_snapshot` | Domain-separated 32-byte digest | Infallible; does not perform structural admission |
| `decode_snapshot` | Canonical `CsrGraph<DenseId>` | Compatibility, length, limit, allocation, and canonicality variants |
| `decode_snapshot_with_control` | Same graph under work and cancellation control | Adds `WorkLimitExceeded` and `Cancelled` |
| `decode_verified_snapshot` | Digest-verified canonical graph | Adds `DigestMismatch` before graph allocation |
| `decode_verified_snapshot_with_control` | Verified graph under explicit control | Adds controlled digest and structural cancellation |

`SnapshotError` exposes stable variants for compatibility, limits, length, allocation, CSR,
control, digest, and core-construction failures. Display strings are diagnostics and may gain more
context in a compatible release; match variants in program logic.
