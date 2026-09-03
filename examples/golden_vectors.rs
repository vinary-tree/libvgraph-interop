use std::fmt::Write;

use libvgraph::{CsrGraph, DenseId};
use libvgraph_interop::{digest_snapshot, encode_snapshot, SemanticProfileId, SnapshotDigest};

fn hexadecimal(bytes: &[u8]) -> Result<String, std::fmt::Error> {
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        write!(&mut output, "{byte:02x}")?;
    }
    Ok(output)
}

fn print_vector(name: &str, bytes: &[u8], digest: SnapshotDigest) -> Result<(), std::fmt::Error> {
    println!("{name}.bytes={}", hexadecimal(bytes)?);
    println!("{name}.digest={}", hexadecimal(digest.as_bytes())?);
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let zero_profile = SemanticProfileId::new([0; 32]);
    let empty = CsrGraph::<DenseId>::from_dense_edges(0, [])?;
    let empty_bytes = encode_snapshot(&empty, zero_profile)?;
    print_vector(
        "empty",
        &empty_bytes,
        digest_snapshot(&empty_bytes, zero_profile),
    )?;

    let mut ascending = [0_u8; 32];
    for (index, byte) in ascending.iter_mut().enumerate() {
        *byte = u8::try_from(index)?;
    }
    let ascending_profile = SemanticProfileId::new(ascending);
    let one_edge = CsrGraph::from_dense_edges(2, [(DenseId::from_raw(0), DenseId::from_raw(1))])?;
    let one_edge_bytes = encode_snapshot(&one_edge, ascending_profile)?;
    print_vector(
        "one_edge",
        &one_edge_bytes,
        digest_snapshot(&one_edge_bytes, ascending_profile),
    )?;
    Ok(())
}
