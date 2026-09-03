use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use libvgraph::{BuildOptions, CsrGraph, DenseId, ReversePolicy};
use libvgraph_interop::{decode_snapshot, encode_snapshot, SemanticProfileId, SnapshotLimits};

fn chain(vertices: u32) -> CsrGraph<DenseId> {
    CsrGraph::from_dense_edges_with_options(
        vertices,
        (0..vertices.saturating_sub(1))
            .map(|source| (DenseId::from_raw(source), DenseId::from_raw(source + 1))),
        BuildOptions {
            reverse: ReversePolicy::Omit,
            ..BuildOptions::default()
        },
    )
    .expect("benchmark chain must build")
}

fn codec_benchmarks(criterion: &mut Criterion) {
    let profile = SemanticProfileId::new([42; 32]);
    let mut group = criterion.benchmark_group("canonical_snapshot");
    for vertices in [1_000_u32, 100_000] {
        let graph = chain(vertices);
        let bytes = encode_snapshot(&graph, profile).expect("benchmark graph must encode");
        group.throughput(Throughput::Bytes(
            u64::try_from(bytes.len()).expect("benchmark bytes must fit u64"),
        ));
        group.bench_with_input(
            BenchmarkId::new("encode", vertices),
            &graph,
            |bencher, graph| {
                bencher.iter(|| {
                    encode_snapshot(black_box(graph), profile)
                        .expect("benchmark encode must succeed")
                });
            },
        );
        group.bench_with_input(
            BenchmarkId::new("decode", vertices),
            &bytes,
            |bencher, bytes| {
                bencher.iter(|| {
                    decode_snapshot(black_box(bytes), profile, SnapshotLimits::unbounded())
                        .expect("benchmark decode must succeed")
                });
            },
        );
    }
    group.finish();
}

criterion_group!(benches, codec_benchmarks);
criterion_main!(benches);
