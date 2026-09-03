mod common;

use std::{
    error::Error,
    sync::{atomic::AtomicBool, Arc},
};

use libvgraph::{BuildOptions, CsrGraph, DenseId, GraphError, ReversePolicy};
use libvgraph_interop::{
    decode_snapshot, decode_snapshot_with_control, decode_verified_snapshot,
    decode_verified_snapshot_with_control, digest_snapshot, encode_snapshot, required_decode_work,
    snapshot_wire_len, DecodeControl, SnapshotDigest, SnapshotError, SnapshotLimits,
    DIGEST_CONTEXT, SNAPSHOT_SCHEMA_ID, SNAPSHOT_VERSION,
};
use proptest::prelude::*;

use common::{dense_graph, profile, raw_edges};

proptest! {
    #[test]
    fn decode_work_bound_matches_the_formal_closed_form(
        vertices in any::<u32>(),
        edges in any::<u32>(),
    ) {
        let expected = 10 + 4 * u64::from(vertices) + 3 * u64::from(edges);
        prop_assert_eq!(required_decode_work(vertices, edges), Ok(expected));
    }

    #[test]
    fn round_trip_and_unique_encoding(
        vertices in 0_u32..32,
        mut edges in prop::collection::vec((any::<u8>(), any::<u8>()), 0..256),
        profile_seed in any::<u8>(),
    ) {
        let semantic_profile = profile(profile_seed);
        let first = dense_graph(vertices, &edges);
        let first_bytes = encode_snapshot(&first, semantic_profile)
            .expect("a bounded canonical graph must encode");
        let decoded = decode_snapshot(
            &first_bytes,
            semantic_profile,
            SnapshotLimits::unbounded(),
        )
        .expect("emitted bytes must decode");
        prop_assert_eq!(decoded.vertex_count(), first.vertex_count());
        prop_assert_eq!(raw_edges(&decoded), raw_edges(&first));
        prop_assert!(!decoded.has_reverse());

        let duplicate = edges.clone();
        edges.reverse();
        edges.extend(duplicate);
        let second = dense_graph(vertices, &edges);
        prop_assert_eq!(
            first_bytes,
            encode_snapshot(&second, semantic_profile)
                .expect("permuted duplicate input must encode")
        );
    }

    #[test]
    fn profile_and_digest_domains_are_separated(
        vertices in 0_u32..16,
        edges in prop::collection::vec((any::<u8>(), any::<u8>()), 0..64),
        first_seed in any::<u8>(),
        second_seed in any::<u8>(),
    ) {
        prop_assume!(first_seed != second_seed);
        let graph = dense_graph(vertices, &edges);
        let first_profile = profile(first_seed);
        let second_profile = profile(second_seed);
        let first = encode_snapshot(&graph, first_profile)
            .expect("first profile must encode");
        let second = encode_snapshot(&graph, second_profile)
            .expect("second profile must encode");
        prop_assert_ne!(&first, &second);
        prop_assert_ne!(
            digest_snapshot(&first, first_profile),
            digest_snapshot(&second, second_profile)
        );
        prop_assert!(decode_snapshot(
            &first,
            second_profile,
            SnapshotLimits::unbounded(),
        ).is_err());
    }

    #[test]
    fn lawful_dense_renaming_is_equivariant(
        vertices in 0_u32..32,
        edges in prop::collection::vec((any::<u8>(), any::<u8>()), 0..256),
    ) {
        let original = dense_graph(vertices, &edges);
        let renamed_edges: Vec<_> = original
            .edges()
            .map(|(source, target)| {
                let rename = |value: u32| vertices - 1 - value;
                (
                    DenseId::from_raw(rename(source.get())),
                    DenseId::from_raw(rename(target.get())),
                )
            })
            .collect();
        let renamed = CsrGraph::from_dense_edges_with_options(
            vertices,
            renamed_edges,
            BuildOptions {
                reverse: ReversePolicy::Omit,
                ..BuildOptions::default()
            },
        )
        .expect("bijective dense renaming must remain in-domain");
        let bytes = encode_snapshot(&renamed, profile(2))
            .expect("lawfully renamed graph must encode");
        let decoded = decode_snapshot(&bytes, profile(2), SnapshotLimits::unbounded())
            .expect("lawfully renamed graph must decode");
        prop_assert_eq!(raw_edges(&decoded), raw_edges(&renamed));
    }
}

#[test]
fn digest_verification_rejects_stale_bytes() {
    let graph = dense_graph(2, &[(0, 1)]);
    let semantic_profile = profile(7);
    let bytes = encode_snapshot(&graph, semantic_profile).expect("graph must encode");
    let digest = digest_snapshot(&bytes, semantic_profile);
    let mut changed = bytes;
    let target_start = 80 + 3 * 4;
    changed[target_start] ^= 1;
    assert!(matches!(
        decode_verified_snapshot(
            &changed,
            semantic_profile,
            digest,
            SnapshotLimits::unbounded(),
        ),
        Err(SnapshotError::DigestMismatch { .. })
    ));
}

#[test]
fn exact_version_schema_and_digest_constants_are_frozen() {
    assert_eq!(SNAPSHOT_VERSION, (1, 0));
    assert_eq!(&SNAPSHOT_SCHEMA_ID, b"LVGI-CSR-FWD-V1!");
    assert_eq!(
        DIGEST_CONTEXT,
        "libvgraph-interop 2026-09-02 17:22:31 UTC canonical snapshot digest v1"
    );
}

#[test]
fn payload_length_and_maximum_count_arithmetic_are_exact() {
    assert_eq!(snapshot_wire_len(0, 0), Ok(84));
    assert_eq!(snapshot_wire_len(2, 1), Ok(96));
    assert_eq!(snapshot_wire_len(u32::MAX, u32::MAX), Ok(34_359_738_444));
    assert_eq!(required_decode_work(u32::MAX, u32::MAX), Ok(30_064_771_075));
}

#[test]
fn opaque_value_accessors_and_diagnostics_are_exact() {
    let profile_bytes = [0x5a; 32];
    let profile = libvgraph_interop::SemanticProfileId::new(profile_bytes);
    assert_eq!(profile.into_bytes(), profile_bytes);

    let digest_bytes = [0xa5; 32];
    let digest = SnapshotDigest::new(digest_bytes);
    assert_eq!(digest.into_bytes(), digest_bytes);
    assert_eq!(
        format!("{digest:?}"),
        "SnapshotDigest(a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5)"
    );

    let control = DecodeControl::with_work_limit(73);
    assert_eq!(control.work_limit(), 73);
    let limits = SnapshotLimits::unbounded();
    assert_eq!(limits.max_vertices, u64::MAX);
    assert_eq!(limits.max_edges, u64::MAX);
    assert_eq!(limits.max_bytes, u64::MAX);

    let error = SnapshotError::from(GraphError::CondensationCycle);
    assert_eq!(error.to_string(), "condensation graph contains a cycle");
    assert!(error.source().is_some());
}

#[test]
fn exact_resource_boundaries_are_admitted() {
    let graph = dense_graph(3, &[(0, 1), (0, 2), (1, 2)]);
    let semantic_profile = profile(13);
    let bytes = encode_snapshot(&graph, semantic_profile).expect("graph must encode");
    let byte_length = u64::try_from(bytes.len()).expect("fixture length must fit u64");
    let work = required_decode_work(3, 3).expect("fixture work must be representable");
    let decoded = decode_snapshot_with_control(
        &bytes,
        semantic_profile,
        SnapshotLimits {
            max_vertices: 3,
            max_edges: 3,
            max_bytes: byte_length,
        },
        DecodeControl::with_work_limit(work),
    )
    .expect("values equal to every configured maximum must be admitted");
    assert_eq!(decoded.vertex_count(), 3);
    assert_eq!(decoded.edge_count(), 3);
}

#[test]
fn digest_changes_when_length_or_payload_changes() {
    let graph = dense_graph(2, &[(0, 1)]);
    let semantic_profile = profile(9);
    let bytes = encode_snapshot(&graph, semantic_profile).expect("graph must encode");
    let digest = digest_snapshot(&bytes, semantic_profile);
    let mut extended = bytes.clone();
    extended.push(0);
    assert_ne!(digest, digest_snapshot(&extended, semantic_profile));
    let mut changed = bytes;
    changed[92] ^= 1;
    assert_ne!(digest, digest_snapshot(&changed, semantic_profile));
}

#[test]
fn work_admission_and_cancellation_are_fail_atomic() {
    let graph = dense_graph(2, &[(0, 1)]);
    let semantic_profile = profile(8);
    let bytes = encode_snapshot(&graph, semantic_profile).expect("graph must encode");
    assert!(matches!(
        decode_snapshot_with_control(
            &bytes,
            semantic_profile,
            SnapshotLimits::unbounded(),
            DecodeControl::with_work_limit(20),
        ),
        Err(SnapshotError::WorkLimitExceeded {
            limit: 20,
            required: 21,
        })
    ));

    let cancelled = AtomicBool::new(true);
    assert!(matches!(
        decode_snapshot_with_control(
            &bytes,
            semantic_profile,
            SnapshotLimits::unbounded(),
            DecodeControl::unlimited().with_cancellation(&cancelled),
        ),
        Err(SnapshotError::Cancelled { completed_bytes: 0 })
    ));

    assert!(matches!(
        decode_verified_snapshot_with_control(
            &bytes,
            semantic_profile,
            SnapshotDigest::new([0; 32]),
            SnapshotLimits::unbounded(),
            DecodeControl::unlimited().with_cancellation(&cancelled),
        ),
        Err(SnapshotError::Cancelled { completed_bytes: 0 })
    ));
}

#[test]
fn verified_decode_enforces_byte_limit_before_digesting() {
    let graph = dense_graph(2, &[(0, 1)]);
    let semantic_profile = profile(12);
    let bytes = encode_snapshot(&graph, semantic_profile).expect("graph must encode");
    let actual = u64::try_from(bytes.len()).expect("fixture length must fit u64");
    assert_eq!(
        decode_verified_snapshot(
            &bytes,
            semantic_profile,
            SnapshotDigest::new([0; 32]),
            SnapshotLimits {
                max_vertices: u64::MAX,
                max_edges: u64::MAX,
                max_bytes: actual - 1,
            },
        ),
        Err(SnapshotError::ByteLimitExceeded {
            limit: actual - 1,
            actual,
        })
    );
}

#[test]
fn deterministic_cancellation_observes_digest_and_both_csr_scans() {
    let semantic_profile = profile(14);
    let digest_input = vec![0_u8; 70_000];
    assert_eq!(
        decode_verified_snapshot_with_control(
            &digest_input,
            semantic_profile,
            SnapshotDigest::new([0; 32]),
            SnapshotLimits {
                max_vertices: u64::MAX,
                max_edges: u64::MAX,
                max_bytes: 70_000,
            },
            DecodeControl::unlimited().with_cancel_after_bytes(2_000),
        ),
        Err(SnapshotError::Cancelled {
            completed_bytes: 65_536,
        })
    );

    let offsets_graph = CsrGraph::<DenseId>::from_dense_edges_with_options(
        2_049,
        [],
        BuildOptions {
            reverse: ReversePolicy::Omit,
            ..BuildOptions::default()
        },
    )
    .expect("offset-heavy fixture must build");
    let offsets_bytes =
        encode_snapshot(&offsets_graph, semantic_profile).expect("offset fixture must encode");
    assert_eq!(
        decode_snapshot_with_control(
            &offsets_bytes,
            semantic_profile,
            SnapshotLimits::unbounded(),
            DecodeControl::unlimited().with_cancel_after_bytes(4_177),
        ),
        Err(SnapshotError::Cancelled {
            completed_bytes: 8_272,
        })
    );

    let complete_edges = (0_u32..64).flat_map(|source| {
        (0_u32..64).map(move |target| (DenseId::from_raw(source), DenseId::from_raw(target)))
    });
    let targets_graph = CsrGraph::from_dense_edges_with_options(
        64,
        complete_edges,
        BuildOptions {
            reverse: ReversePolicy::Omit,
            ..BuildOptions::default()
        },
    )
    .expect("target-heavy fixture must build");
    let targets_bytes =
        encode_snapshot(&targets_graph, semantic_profile).expect("target fixture must encode");
    assert_eq!(
        decode_snapshot_with_control(
            &targets_bytes,
            semantic_profile,
            SnapshotLimits::unbounded(),
            DecodeControl::unlimited().with_cancel_after_bytes(4_177),
        ),
        Err(SnapshotError::Cancelled {
            completed_bytes: 8_272,
        })
    );
}

#[test]
fn concurrent_readers_are_deterministic_and_share_no_mutable_codec_state() {
    let graph = dense_graph(5, &[(0, 1), (1, 2), (2, 3), (3, 4), (4, 0)]);
    let semantic_profile = profile(11);
    let bytes = Arc::new(encode_snapshot(&graph, semantic_profile).expect("graph must encode"));
    let expected = raw_edges(&graph);
    let mut threads = Vec::with_capacity(8);
    for _ in 0..8 {
        let bytes = Arc::clone(&bytes);
        let expected = expected.clone();
        threads.push(std::thread::spawn(move || {
            let decoded = decode_snapshot(&bytes, semantic_profile, SnapshotLimits::unbounded())
                .expect("shared immutable bytes must decode");
            assert_eq!(raw_edges(&decoded), expected);
        }));
    }
    for thread in threads {
        thread.join().expect("reader thread must complete");
    }
}
