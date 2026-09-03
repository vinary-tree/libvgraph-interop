#![no_main]

use libfuzzer_sys::fuzz_target;
use libvgraph_interop::{
    decode_snapshot, decode_verified_snapshot, digest_snapshot, SemanticProfileId, SnapshotDigest,
    SnapshotLimits,
};

fuzz_target!(|data: &[u8]| {
    let limits = SnapshotLimits {
        max_vertices: 4_096,
        max_edges: 16_384,
        max_bytes: 1 << 20,
    };

    let mut arbitrary_profile = [0_u8; 32];
    let prefix = data.len().min(arbitrary_profile.len());
    arbitrary_profile[..prefix].copy_from_slice(&data[..prefix]);
    let arbitrary_profile = SemanticProfileId::new(arbitrary_profile);
    let _ = decode_snapshot(data, arbitrary_profile, limits);
    if data.len() <= 1 << 20 {
        let exact = digest_snapshot(data, arbitrary_profile);
        let _ = decode_verified_snapshot(data, arbitrary_profile, exact, limits);
        let _ = decode_verified_snapshot(
            data,
            arbitrary_profile,
            SnapshotDigest::new([0; 32]),
            limits,
        );
    }

    if data.len() >= 64 {
        let mut embedded_profile = [0_u8; 32];
        embedded_profile.copy_from_slice(&data[32..64]);
        let embedded_profile = SemanticProfileId::new(embedded_profile);
        let _ = decode_snapshot(data, embedded_profile, limits);
        if data.len() <= 1 << 20 {
            let exact = digest_snapshot(data, embedded_profile);
            let _ = decode_verified_snapshot(data, embedded_profile, exact, limits);
            let _ = decode_verified_snapshot(
                data,
                embedded_profile,
                SnapshotDigest::new([0; 32]),
                limits,
            );
        }
    }
});
