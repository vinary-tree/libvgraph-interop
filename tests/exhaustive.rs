mod common;

use libvgraph::{BuildOptions, CsrGraph, DenseId, ReversePolicy};
use libvgraph_interop::{decode_snapshot, encode_snapshot, SemanticProfileId, SnapshotLimits};

use common::{graph_from_mask, raw_edges};

fn permutations(vertices: u32) -> &'static [&'static [u32]] {
    match vertices {
        0 => &[&[]],
        1 => &[&[0]],
        2 => &[&[0, 1], &[1, 0]],
        3 => &[
            &[0, 1, 2],
            &[0, 2, 1],
            &[1, 0, 2],
            &[1, 2, 0],
            &[2, 0, 1],
            &[2, 1, 0],
        ],
        _ => unreachable!("the exhaustive corpus stops at three vertices"),
    }
}

#[test]
fn every_directed_graph_through_three_vertices_refines_the_formal_contract() {
    let profiles = [
        SemanticProfileId::new([0; 32]),
        SemanticProfileId::new([1; 32]),
        SemanticProfileId::new([u8::MAX; 32]),
    ];
    let mut graphs = 0_u64;
    let mut encodings = 0_u64;
    let mut renamings = 0_u64;
    let mut prefix_rejections = 0_u64;

    for vertices in 0..=3_u32 {
        let graph_count = 1_u64 << (vertices * vertices);
        for mask in 0..graph_count {
            let graph = graph_from_mask(vertices, mask);
            graphs += 1;
            for semantic_profile in profiles {
                let bytes = encode_snapshot(&graph, semantic_profile)
                    .expect("finite exhaustive graph must encode");
                let decoded =
                    decode_snapshot(&bytes, semantic_profile, SnapshotLimits::unbounded())
                        .expect("finite exhaustive graph must decode");
                assert_eq!(raw_edges(&decoded), raw_edges(&graph));
                encodings += 1;

                for &permutation in permutations(vertices) {
                    let renamed_edges: Vec<_> = graph
                        .edges()
                        .map(|(source, target)| {
                            (
                                DenseId::from_raw(permutation[source.get() as usize]),
                                DenseId::from_raw(permutation[target.get() as usize]),
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
                    .expect("permutation must preserve the dense domain");
                    let renamed_bytes = encode_snapshot(&renamed, semantic_profile)
                        .expect("renamed graph must encode");
                    let renamed_decoded = decode_snapshot(
                        &renamed_bytes,
                        semantic_profile,
                        SnapshotLimits::unbounded(),
                    )
                    .expect("renamed graph must decode");
                    assert_eq!(raw_edges(&renamed_decoded), raw_edges(&renamed));
                    renamings += 1;
                }

                for prefix in 0..bytes.len() {
                    assert!(decode_snapshot(
                        &bytes[..prefix],
                        semantic_profile,
                        SnapshotLimits::unbounded(),
                    )
                    .is_err());
                    prefix_rejections += 1;
                }
            }
        }
    }

    assert_eq!(graphs, 531);
    assert_eq!(encodings, 1_593);
    assert_eq!(renamings, 9_321);
    assert_eq!(prefix_rejections, 180_696);
}
