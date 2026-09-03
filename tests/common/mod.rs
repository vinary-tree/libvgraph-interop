#![allow(dead_code)]

use libvgraph::{BuildOptions, CsrGraph, DenseId, ReversePolicy};
use libvgraph_interop::SemanticProfileId;

pub fn profile(seed: u8) -> SemanticProfileId {
    SemanticProfileId::new([seed; 32])
}

pub fn dense_graph(vertices: u32, raw_edges: &[(u8, u8)]) -> CsrGraph<DenseId> {
    let edges = raw_edges
        .iter()
        .filter(|_| vertices != 0)
        .map(|&(source, target)| {
            (
                DenseId::from_raw(u32::from(source) % vertices),
                DenseId::from_raw(u32::from(target) % vertices),
            )
        });
    CsrGraph::from_dense_edges_with_options(
        vertices,
        edges,
        BuildOptions {
            reverse: ReversePolicy::Omit,
            ..BuildOptions::default()
        },
    )
    .expect("bounded test edges must form a canonical dense graph")
}

pub fn graph_from_mask(vertices: u32, mask: u64) -> CsrGraph<DenseId> {
    let mut edges = Vec::with_capacity(vertices as usize * vertices as usize);
    let mut bit = 0_u32;
    for source in 0..vertices {
        for target in 0..vertices {
            if mask & (1_u64 << bit) != 0 {
                edges.push((DenseId::from_raw(source), DenseId::from_raw(target)));
            }
            bit += 1;
        }
    }
    CsrGraph::from_dense_edges_with_options(
        vertices,
        edges,
        BuildOptions {
            reverse: ReversePolicy::Omit,
            ..BuildOptions::default()
        },
    )
    .expect("a finite mask must define a valid dense graph")
}

pub fn raw_edges(graph: &CsrGraph<DenseId>) -> Vec<(u32, u32)> {
    graph
        .edges()
        .map(|(source, target)| (source.get(), target.get()))
        .collect()
}

pub fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut encoded = String::with_capacity(bytes.len() * 2);
    for &byte in bytes {
        encoded.push(char::from(DIGITS[(byte >> 4) as usize]));
        encoded.push(char::from(DIGITS[(byte & 0x0f) as usize]));
    }
    encoded
}
