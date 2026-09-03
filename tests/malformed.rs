mod common;

use libvgraph_interop::{
    decode_snapshot, encode_snapshot, SnapshotError, SnapshotLimits, SNAPSHOT_HEADER_BYTES,
};
use proptest::prelude::*;

use common::{dense_graph, profile};

fn base() -> Vec<u8> {
    encode_snapshot(&dense_graph(3, &[(0, 1), (0, 2), (1, 2)]), profile(3))
        .expect("fixture graph must encode")
}

proptest! {
    #[test]
    fn every_generated_unsupported_version_is_rejected(major in any::<u16>(), minor in any::<u16>()) {
        prop_assume!((major, minor) != (1, 0));
        let mut bytes = base();
        bytes[24..26].copy_from_slice(&major.to_le_bytes());
        bytes[26..28].copy_from_slice(&minor.to_le_bytes());
        prop_assert_eq!(
            decode_snapshot(&bytes, profile(3), SnapshotLimits::unbounded()),
            Err(SnapshotError::VersionMismatch { major, minor })
        );
    }
}

#[test]
fn every_strict_prefix_and_trailing_suffix_is_rejected() {
    let bytes = base();
    for prefix in 0..bytes.len() {
        assert!(
            decode_snapshot(&bytes[..prefix], profile(3), SnapshotLimits::unbounded()).is_err()
        );
    }
    let mut trailing = bytes;
    trailing.push(0);
    assert!(matches!(
        decode_snapshot(&trailing, profile(3), SnapshotLimits::unbounded()),
        Err(SnapshotError::SnapshotLengthMismatch { .. })
    ));
}

#[test]
fn header_failure_matrix_is_exact() {
    let original = base();

    assert_eq!(
        decode_snapshot(
            &original[..SNAPSHOT_HEADER_BYTES],
            profile(3),
            SnapshotLimits::unbounded(),
        ),
        Err(SnapshotError::SnapshotLengthMismatch {
            expected: u64::try_from(original.len()).expect("fixture length must fit u64"),
            actual: SNAPSHOT_HEADER_BYTES as u64,
        })
    );

    let mut bytes = original.clone();
    bytes[0] ^= 1;
    assert_eq!(
        decode_snapshot(&bytes, profile(3), SnapshotLimits::unbounded()),
        Err(SnapshotError::MagicMismatch)
    );

    let mut bytes = original.clone();
    bytes[8] ^= 1;
    assert!(matches!(
        decode_snapshot(&bytes, profile(3), SnapshotLimits::unbounded()),
        Err(SnapshotError::SchemaMismatch { .. })
    ));

    for version in [(0_u16, 9_u16), (1, 1), (2, 0)] {
        let mut bytes = original.clone();
        bytes[24..26].copy_from_slice(&version.0.to_le_bytes());
        bytes[26..28].copy_from_slice(&version.1.to_le_bytes());
        assert_eq!(
            decode_snapshot(&bytes, profile(3), SnapshotLimits::unbounded()),
            Err(SnapshotError::VersionMismatch {
                major: version.0,
                minor: version.1,
            })
        );
    }

    let mut bytes = original.clone();
    bytes[28..32].copy_from_slice(&1_u32.to_le_bytes());
    assert_eq!(
        decode_snapshot(&bytes, profile(3), SnapshotLimits::unbounded()),
        Err(SnapshotError::UnknownFlags { flags: 1 })
    );

    assert!(matches!(
        decode_snapshot(&original, profile(4), SnapshotLimits::unbounded()),
        Err(SnapshotError::ProfileMismatch { .. })
    ));

    let mut bytes = original;
    bytes[72..80].copy_from_slice(&0_u64.to_le_bytes());
    assert!(matches!(
        decode_snapshot(&bytes, profile(3), SnapshotLimits::unbounded()),
        Err(SnapshotError::PayloadLengthMismatch { .. })
    ));
}

#[test]
fn canonical_csr_failure_matrix_is_exact() {
    let original = base();
    let offsets = SNAPSHOT_HEADER_BYTES;
    let targets = offsets + 4 * 4;

    let mut bytes = original.clone();
    bytes[offsets..offsets + 4].copy_from_slice(&1_u32.to_le_bytes());
    assert_eq!(
        decode_snapshot(&bytes, profile(3), SnapshotLimits::unbounded()),
        Err(SnapshotError::OffsetOrigin { actual: 1 })
    );

    let mut bytes = original.clone();
    bytes[offsets + 4..offsets + 8].copy_from_slice(&3_u32.to_le_bytes());
    bytes[offsets + 8..offsets + 12].copy_from_slice(&2_u32.to_le_bytes());
    assert!(matches!(
        decode_snapshot(&bytes, profile(3), SnapshotLimits::unbounded()),
        Err(SnapshotError::OffsetOrder { .. })
    ));

    let mut bytes = original.clone();
    bytes[offsets + 4..offsets + 8].copy_from_slice(&1_u32.to_le_bytes());
    bytes[offsets + 8..offsets + 12].copy_from_slice(&2_u32.to_le_bytes());
    bytes[offsets + 12..offsets + 16].copy_from_slice(&2_u32.to_le_bytes());
    assert_eq!(
        decode_snapshot(&bytes, profile(3), SnapshotLimits::unbounded()),
        Err(SnapshotError::OffsetTerminal {
            expected: 3,
            actual: 2,
        })
    );

    let mut bytes = original.clone();
    bytes[targets..targets + 4].copy_from_slice(&3_u32.to_le_bytes());
    assert!(matches!(
        decode_snapshot(&bytes, profile(3), SnapshotLimits::unbounded()),
        Err(SnapshotError::TargetOutOfRange { .. })
    ));

    for pair in [(2_u32, 2_u32), (2, 1)] {
        let mut bytes = original.clone();
        bytes[targets..targets + 4].copy_from_slice(&pair.0.to_le_bytes());
        bytes[targets + 4..targets + 8].copy_from_slice(&pair.1.to_le_bytes());
        assert!(matches!(
            decode_snapshot(&bytes, profile(3), SnapshotLimits::unbounded()),
            Err(SnapshotError::AdjacencyOrder { .. })
        ));
    }
}

#[test]
fn all_resource_limits_reject_before_graph_publication() {
    let bytes = base();
    let length = u64::try_from(bytes.len()).expect("fixture length must fit u64");
    for limits in [
        SnapshotLimits {
            max_vertices: 2,
            max_edges: 3,
            max_bytes: length,
        },
        SnapshotLimits {
            max_vertices: 3,
            max_edges: 2,
            max_bytes: length,
        },
        SnapshotLimits {
            max_vertices: 3,
            max_edges: 3,
            max_bytes: length - 1,
        },
    ] {
        assert!(decode_snapshot(&bytes, profile(3), limits).is_err());
    }
}
