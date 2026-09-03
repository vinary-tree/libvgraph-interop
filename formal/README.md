# Formal contract provenance

Formal-tool names and shared graph/resource terminology are defined in the
[project glossary](../docs/glossary.md).

Production code in this repository refines a contract completed before its implementation. The
authoritative source is `vinary-tree/libvgraph` commit
[`e381330d16f67258a4a6525d08f89ae9edc627a7`](https://github.com/vinary-tree/libvgraph/commit/e381330d16f67258a4a6525d08f89ae9edc627a7).

`source.commit` is the single canonical formal-source identity consumed by local verification,
continuous integration, and release automation. `contract.sha256` binds all 28 repository-resident
proof sources, configurations,
required-red inputs, dependency locks, and gate definitions to their exact blobs.
`scripts/verify-formal-provenance.sh` verifies the signed Git commit against the permitted signer,
rejects any missing, duplicate, reordered, substituted, or additional manifest entry, resolves
each blob from the commit object, and checks its digest. Later worktree changes therefore cannot
silently redefine the preimplementation contract.

`refinement.tsv` maps all 76 extracted invariants to production source or acceptance tests.
`scripts/check-refinement.sh` projects the frozen formal ledger and demands exact ordered identity
of every invariant, layer, formal artifact, and formal symbol. It then resolves every formal symbol
from the frozen commit and every production symbol from this worktree. The mapping does not
replace the proofs or behavioral tests; it makes their correspondence auditable.

The verified results were:

- 19 Rocq closed-assumption reports;
- 33,270 TLC states generated, 16,900 distinct states, depth 15, and no positive-model error;
- four expected-failing TLC causal mutants, including explicit native-depth growth;
- 644 release states generated, 452 distinct states at depth 7, and nine expected-failing release
  causal mutants, including an undeclared portable-tool dependency and a mismatched formal source;
- 9 Z3 unsatisfiable obligations and 2 constructive satisfiable witnesses;
- 6 Verus obligations verified with no error; and
- 531 graphs, 1,593 profile encodings, 9,321 lawful renamings, and 180,696 strict-prefix
  rejections in the independent executable model.
