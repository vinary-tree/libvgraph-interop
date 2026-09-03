mod common;

use libvgraph_interop::{
    decode_snapshot, digest_snapshot, encode_snapshot, SemanticProfileId, SnapshotLimits,
};

use common::{dense_graph, hex, profile, raw_edges};

#[test]
fn exact_version_1_golden_vectors_are_stable() {
    let empty = dense_graph(0, &[]);
    let empty_bytes = encode_snapshot(&empty, profile(0)).expect("empty graph must encode");
    assert_eq!(
        hex(&empty_bytes),
        "4c5647534e5000014c5647492d4353522d4657442d563121010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000"
    );

    let mut ascending = [0_u8; 32];
    for (index, byte) in ascending.iter_mut().enumerate() {
        *byte = u8::try_from(index).expect("profile index must fit u8");
    }
    let one_edge = dense_graph(2, &[(0, 1)]);
    let bytes = encode_snapshot(&one_edge, SemanticProfileId::new(ascending))
        .expect("one-edge graph must encode");
    assert_eq!(
        hex(&bytes),
        "4c5647534e5000014c5647492d4353522d4657442d5631210100000000000000000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f0200000001000000100000000000000000000000010000000100000001000000"
    );
    let decoded = decode_snapshot(
        &bytes,
        SemanticProfileId::new(ascending),
        SnapshotLimits::unbounded(),
    )
    .expect("golden vector must decode");
    assert_eq!(raw_edges(&decoded), vec![(0, 1)]);

    assert_eq!(
        hex(digest_snapshot(&empty_bytes, profile(0)).as_bytes()),
        "1b9a21818f39e2f8d5bd71940f2d61413afcc2dbaf4a18c90b13b2d26dc504f9"
    );
    assert_eq!(
        hex(digest_snapshot(&bytes, SemanticProfileId::new(ascending)).as_bytes()),
        "2cfdc84873b8c4bfa69fb6094e33bf02e50e1f321982e395263bfd25d96f3565"
    );
}
