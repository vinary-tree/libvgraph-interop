# Literate snapshot algorithms

This document presents the production algorithms with explicit preconditions, postconditions, and
failure points. It follows Knuth's literate-programming principle of explaining the program and its
rationale together ([“Literate Programming”](https://doi.org/10.1093/comjnl/27.2.97)). Shared
terms and symbols are defined in the [glossary](../glossary.md).

The pseudocode names the corresponding Rust functions in [`src/wire.rs`](../../src/wire.rs),
[`src/digest.rs`](../../src/digest.rs), and [`src/control.rs`](../../src/control.rs). The operation
`REJECT`, given typed error $`e`$, returns $`e`$ without publishing a graph. The operation
`OBSERVE`, given control $`c`$ and completed byte position $`n`$, applies both the deterministic
byte-progress threshold and the caller-owned atomic cancellation flag.

## Exact encoder

`encode_snapshot` exploits the canonicality already established by the private representation of
`CsrGraph`; repeating the core validator would add a redundant $`O(V + E)`$ pass.

**Preconditions:** `graph` is a safely constructed `CsrGraph<K>` and `profile` is exactly 32 bytes.

```text
ENCODE-SNAPSHOT(graph, profile):
    convert graph vertex and edge counts to u32, or REJECT(arithmetic overflow)
    compute 80 + 4 × (V + 1 + E) with checked u64 and usize arithmetic,
        or REJECT(arithmetic overflow)
    request at least that many output bytes, or REJECT(allocation failure)
    append magic, schema, version 1.0, zero flags, profile, counts, and payload length
    append every forward offset as little-endian u32
    append every forward target as little-endian u32
    assert that initialized output length equals the computed wire length
    return output
```

**Postconditions on success:** the returned vector has the exact version-1 length and field order;
its payload is the graph's canonical forward CSR; stable labels and reverse adjacency are absent.

## Controlled digest

`digest_snapshot_with_control` streams the tagged invocation instead of allocating a concatenated
preimage. The 64 KiB chunk size preserves BLAKE3's bulk implementation while defining cooperative
cancellation checkpoints.

**Preconditions:** `bytes` is any byte slice; structural validity is not required.

```text
DIGEST-CONTROLLED(bytes, profile, control):
    OBSERVE(control, 0), or REJECT(cancelled)
    initialize BLAKE3 derive-key mode with the fixed context
    absorb schema, profile, little-endian u64 byte length
    completed := 0
    for each consecutive bytes chunk of at most 64 KiB:
        absorb chunk
        completed := completed + chunk length using checked arithmetic
        OBSERVE(control, completed), or REJECT(cancelled)
    return the 32-byte BLAKE3 hash value
```

**Postconditions on success:** the digest binds the context, schema, profile, exact byte length,
and every byte in order. The result authenticates nothing unless its expected value arrives through
an authenticated channel.

## Ordinary admission

`decode_snapshot_with_control` deliberately rejects noncanonical bytes rather than repairing them.
The cumulative 1,024-word checkpoint counter spans offsets and targets, so changing row boundaries
cannot delay a structural-copy observation.

**Preconditions:** `bytes` may be hostile; the caller supplies the expected profile, finite limits
for an untrusted boundary, and a control value. If atomic cancellation is requested, the caller
keeps the flag true until return.

```text
DECODE-CONTROLLED(bytes, expected_profile, limits, control):
    OBSERVE(control, 0), or REJECT(cancelled)
    enforce complete-byte limit
    require the complete fixed header
    require exact magic, schema, version 1.0, zero flags, and expected profile
    derive payload and total lengths with checked arithmetic
    require declared payload length and actual complete length to be exact
    require V and E within caller limits
    require logical work 10 + 4V + 3E within the control budget
    OBSERVE(control, 0), or REJECT(cancelled)

    request minimum capacities for V + 1 offsets and E targets,
        or REJECT(allocation failure)
    cursor := 80; inspected_words := 0
    copy each offset and then each target from the monotone cursor
    after every cumulative 1,024 words:
        OBSERVE(control, cursor), or REJECT(cancelled)
    require cursor equals complete byte length
    OBSERVE(control, cursor), or REJECT(cancelled)

    request minimum capacity for V dense nodes, or REJECT(allocation failure)
    materialize dense nodes 0 through V - 1 iteratively
    call CsrGraph::try_from_parts once
        // one unpolled, stack-safe O(V + E) canonical-import scan
        // reject bad offsets, targets, or row order
    OBSERVE(control, cursor), or REJECT(cancelled)
    return the canonical owned graph
```

**Postconditions on success:** the graph is canonical, contains exactly the admitted topology, and
is published only after the final cancellation observation. On every error, all request-local
buffers are released and no graph is returned.

## Verified admission

`decode_verified_snapshot_with_control` orders cheap resource rejection before hashing, and digest
rejection before graph allocation.

**Preconditions:** those of ordinary admission, plus an expected digest obtained through the
caller's trust mechanism.

```text
DECODE-VERIFIED-CONTROLLED(bytes, profile, expected_digest, limits, control):
    enforce complete-byte limit
    actual_digest := DIGEST-CONTROLLED(bytes, profile, control)
    compare actual_digest with expected_digest using BLAKE3 Hash equality
    if unequal: REJECT(digest mismatch)
    return DECODE-CONTROLLED(bytes, profile, limits, control)
```

**Postconditions on success:** ordinary structural admission holds and the complete tagged digest
matches. The digest comparison is constant-time for its 32 bytes; hashing, structural admission,
and typed error selection are not constant-time.

## Stack and concurrency rationale

All data-dependent repetition above is a bounded loop over flat buffers. No call recurs on graph
structure, so native call depth is independent of $`V`$, $`E`$, and path depth. Each invocation owns
its buffers and cursor. Request-level parallelism therefore needs no codec-global lock, while the
single-snapshot loops remain sequential to preserve contiguous access, exact error precedence, and
low coordination overhead.
