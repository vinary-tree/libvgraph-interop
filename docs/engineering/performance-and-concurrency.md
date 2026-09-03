# Performance and concurrency engineering

The codec is designed for predictable memory bandwidth, exact logical lengths, and request-level
parallelism. Algorithm selection follows the formally fixed flat representation.

## Complexity

| Operation | Time | Additional owned memory | Notes |
|---|---:|---:|---|
| Encode | $`O(V + E)`$ | Exact initialized output bytes | One sequential pass after one minimum-capacity request |
| Decode header | $`O(1)`$ | $`O(1)`$ | All limits precede allocation |
| Decode payload and import | $`O(V + E)`$ | $`O(V + E)`$ | Flat arrays; core canonical validator runs once |
| Digest | $`O(B)`$ | $`O(1)`$ | BLAKE3 streams $`B`$ input bytes |
| Verified decode | $`O(B + V + E)`$ | $`O(V + E)`$ | Stale digests reject before graph allocation |

The exact logical decode charge is:

```math
W(V,E) = 8 + 2(V + 1) + 2V + 3E = 10 + 4V + 3E.
```

This deterministic, conservative logical charge is admitted from validated header counts before
request-local vectors are allocated. It covers offset and target materialization, dense-node
materialization, and canonical import scans; it is a budget unit rather than an instruction count.
It excludes BLAKE3 compression work: verified decoding bounds that work by checking
`SnapshotLimits::max_bytes` before hashing the slice.

## Allocation discipline

The encoder asks for at least the wire length once. The decoder asks for at least the declared
offset, target, and dense-node lengths with `try_reserve_exact`, turning reservation failure into
`SnapshotError` rather than relying on incremental growth. The initialized lengths and logical
element counts are exact; the allocator may provide additional physical capacity. The codec never
materializes the conceptual digest preimage.

## Request-level parallelism

Independent encode, digest, and decode calls share only immutable code. Callers may distribute
requests across a thread pool, Rayon scope, async blocking executor, or schedlib without a
codec-global lock. With identical inputs, limits, an inactive cancellation source, and successful
allocation, results remain byte-for-byte deterministic across worker counts and schedules.

## Why the word loop is sequential

Offsets and targets are emitted in fixed order and validation is a contiguous memory scan. Inner
parallelism would add partitions, synchronization, failure arbitration, and small-work overhead to
a bandwidth-oriented path. The implementation therefore parallelizes requests rather than words.
Any proposed single-snapshot parallel path requires profiling evidence and must preserve exact
error precedence, cancellation, allocation bounds, and bytes.

## Cancellation granularity

CSR word copying observes cancellation every 1,024 words, before dense-node materialization, and
at publication. Verified digesting observes cancellation after each 64 KiB BLAKE3 chunk so the
cryptographic implementation retains vectorized bulk work. Between the last copy checkpoint and
publication, `libvgraph` performs one stack-safe $`O(V + E)`$ canonical-import scan without a
cancellation callback; that scan is the maximum uninterruptible interval. The optional
byte-progress threshold is evaluated at digest and structural-copy checkpoints independently.
Relaxed atomic loads carry no data synchronization. A caller using the atomic source must keep it
true after requesting cancellation until the operation returns; cancellation races intentionally
make the selected rejection checkpoint schedule-dependent.

## Benchmark protocol

`benches/codec.rs` measures chains of 1,000 and 100,000 vertices with Criterion byte throughput.
Release evidence must:

1. record the source commit, Rust version, CPU model, governor, affinity, and command;
2. run under the campaign RSS, no-swap, task, and CPU limits;
3. compare only changed codec paths and exclude unrelated graph-algorithm studies;
4. retain raw Criterion output; and
5. treat regressions as hypotheses to profile rather than reasons to weaken the contract.

Heaptrack, when used, must run headlessly. Repository-backed `target` storage is mandatory because
`/tmp` is a memory-backed filesystem on the campaign host.
