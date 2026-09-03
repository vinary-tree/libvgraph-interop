# Security and resource safety

Snapshot bytes are untrusted until all admission gates succeed. An attacker may control every
byte, declared count, version, flag, profile, cache entry, truncation point, and request timing.

## Fail-closed publication

Let magic, schema, version, flags, profile, length, budget, canonicality, digest, and cancellation
checks be $`M`$, $`S`$, $`V`$, $`F`$, $`R`$, $`L`$, $`B`$, $`C`$, $`D`$, and $`X`$,
respectively. Exact publication requires:

```math
P = M \land S \land V \land F \land R \land L \land B
    \land C \land D \land \neg X.
```

No failed gate is normalized into a successful value. TLA+ causal mutants prove that omitting
schema, canonicality, or cancellation enforcement admits an explicit `PublicationSound`
counterexample.

## Allocation and arithmetic

The complete-slice byte limit is checked before digesting or reading a header. Header fields are
validated before allocation. Payload, total length, host conversion, and logical work use checked
arithmetic. Only exact declared and actual lengths may request array capacity, and every request is
fallible. Logical element counts are exact; allocator-selected physical capacity may be larger.

Callers must select finite limits appropriate to their service. `SnapshotLimits::unbounded()` is a
representation-wide convenience, not an untrusted-network policy.

## Canonicality

The decoder rejects nonzero origin offsets, decreasing offsets, a wrong terminal offset,
out-of-range targets, duplicate or decreasing row targets, truncation, and trailing bytes. It does
not repair or normalize input because multiple hostile representations must not acquire one trusted
identity silently.

## Digest security

BLAKE3 derive-key mode binds a globally unique context to schema, profile, exact length, and bytes
([reviewed specification at commit `ac784c9`](https://github.com/BLAKE3-team/BLAKE3-specs/blob/ac784c9f22a48327782f042ec2f4d8126b3b1744/blake3.tex)).
Digest comparison uses BLAKE3's `Hash` equality, whose exact version-1.8.7 implementation delegates
to a 32-byte constant-time comparison
([pinned source](https://github.com/BLAKE3-team/BLAKE3/blob/f3149ec5bb5449af877ba20377a11008ff499fa2/src/lib.rs)).

The digest is not authentication by itself. An attacker who controls both bytes and expected digest
can replace both. It also provides no confidentiality. Protect the expected value with an
authenticated channel, message authentication code, or signature, and encrypt sensitive snapshots
in the owning layer. Collision-intolerant evidence should retain complete canonical bytes as well.
Only the 32-byte digest equality is constant-time; hashing, admission, and typed error selection are
not designed to hide timing.

## Work, cancellation, and stack

All data-dependent iteration is explicit over flat slices and vectors. Graph depth never adds a
native call frame. A deterministic structural-work limit rejects from admitted counts before
allocation. The byte limit independently bounds digest work and is checked before hashing begins.
Atomic cancellation is sampled during CSR copying and digest scans and at the return boundary;
observation never publishes a partial graph. The intervening `libvgraph` canonical-import scan is
linear and stack-safe but unpolled, so its $`O(V + E)`$ completion is the maximum uninterruptible
interval. A caller must keep an atomic cancellation request true until the operation returns. A
deterministic byte-progress threshold exercises the digest and structural-copy checkpoints without
timing races and can impose an additional per-phase bound.

## Error disclosure

Typed errors report only structural fields, observed values, limits, and request progress. They do
not include unrelated memory, semantic-profile source material, credentials, or the complete
hostile payload. Applications must not treat display text as a stable protocol.

## Residual risks

- A maximum admitted input consumes its configured linear CPU and memory budget.
- Digest collision resistance depends on BLAKE3, not the structural proofs.
- Profile correctness depends on the domain adapter that constructs it.
- Dense renaming changes bytes and digests unless the canonical transported graph is identical.
- New schemas require explicit deployment and migration before version-1 readers can consume them.

These are explicit boundary conditions rather than silent approximations.
