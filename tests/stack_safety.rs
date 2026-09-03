use libvgraph::{BuildOptions, CsrGraph, DenseId, ReversePolicy};
use libvgraph_interop::{
    decode_snapshot, decode_verified_snapshot, digest_snapshot, encode_snapshot, SemanticProfileId,
    SnapshotError, SnapshotLimits,
};
use std::panic::{catch_unwind, AssertUnwindSafe};

#[test]
fn deep_codec_lifecycle_is_native_stack_independent() {
    const VERTICES: u32 = 100_000;
    std::thread::Builder::new()
        .name("libvgraph-interop-small-stack".to_owned())
        .stack_size(64 * 1024)
        .spawn(|| {
            let mut edges = Vec::with_capacity(VERTICES as usize - 1);
            edges.extend(
                (0..VERTICES - 1)
                    .map(|source| (DenseId::from_raw(source), DenseId::from_raw(source + 1))),
            );
            let graph = CsrGraph::from_dense_edges_with_options(
                VERTICES,
                edges,
                BuildOptions {
                    reverse: ReversePolicy::Omit,
                    ..BuildOptions::default()
                },
            )
            .expect("deep chain must build");
            let semantic_profile = SemanticProfileId::new([10; 32]);
            let bytes = encode_snapshot(&graph, semantic_profile).expect("deep graph must encode");
            let digest = digest_snapshot(&bytes, semantic_profile);
            let decoded = decode_snapshot(&bytes, semantic_profile, SnapshotLimits::unbounded())
                .expect("deep graph must decode");
            assert_eq!(decoded, graph);
            drop(decoded);
            let verified = decode_verified_snapshot(
                &bytes,
                semantic_profile,
                digest,
                SnapshotLimits::unbounded(),
            )
            .expect("deep graph digest and structure must verify");
            assert_eq!(verified, graph);

            let mut malformed = bytes;
            let final_word = malformed.len() - 4;
            malformed[final_word..].copy_from_slice(&VERTICES.to_le_bytes());
            {
                let error =
                    decode_snapshot(&malformed, semantic_profile, SnapshotLimits::unbounded())
                        .expect_err(
                            "an out-of-range final target must reject after buffer materialization",
                        );
                assert!(matches!(
                    error,
                    SnapshotError::TargetOutOfRange {
                        target,
                        vertex_count,
                        ..
                    } if target == VERTICES && vertex_count == VERTICES
                ));
            }

            let unwind = catch_unwind(AssertUnwindSafe(move || {
                assert_eq!(
                    verified.vertex_count(),
                    usize::try_from(VERTICES).expect("100,000 vertices must fit usize")
                );
                panic!("intentional stack-safety unwind probe");
            }));
            assert!(unwind.is_err(), "the deliberate unwind probe must unwind");
        })
        .expect("small-stack thread must start")
        .join()
        .expect("small-stack lifecycle must complete");
}
