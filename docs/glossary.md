# Glossary and notation

This glossary defines terminology shared by the architecture, theory, verification, security, and
usage documents. Individual documents define local symbols before using them.

| Term | Definition |
|---|---|
| Admission | The fail-closed conversion of untrusted snapshot bytes into a published canonical graph. Failure returns a typed error and no graph. |
| BLAKE3 | A cryptographic hash function used here in derive-key mode for domain-separated snapshot digests. The reviewed algorithm is the [specification at commit `ac784c9`](https://github.com/BLAKE3-team/BLAKE3-specs/blob/ac784c9f22a48327782f042ec2f4d8126b3b1744/blake3.tex). |
| Code property graph (CPG) | A graph representation combining syntax, control-flow, and data-flow relations for program analysis. The term follows Yamaguchi et al., [“Modeling and Discovering Vulnerabilities with Code Property Graphs”](https://doi.org/10.1109/SP.2014.44). CPG semantics remain outside this crate. |
| Compressed sparse row (CSR) | A graph representation with a contiguous target array and an offset array delimiting each source row. This crate serializes only canonical forward CSR. |
| Central processing unit (CPU) | The processor resource constrained by verification scopes and identified in benchmark evidence. |
| Fiber | An indexed member of a family of sets. The semantic-profile fibers in this crate are admitted-byte subsets; they do not by themselves constitute a categorical fibration. |
| GitHub Flavored Markdown (GFM) | GitHub's CommonMark-based Markdown dialect, defined by the [GFM specification](https://github.github.com/gfm/). Documentation and mathematical delimiters target this renderer. |
| Minimum supported Rust version (MSRV) | The oldest Rust toolchain that the crate promises to support and tests as a release gate. |
| Native stack depth | The number of active machine call frames. A stack-safe graph operation keeps this independent of graph depth by using flat iterative state. |
| OpenID Connect (OIDC) | A federated identity protocol used by GitHub Actions and crates.io to exchange a short-lived, workflow-bound publishing credential instead of storing a long-lived token. |
| Resident set size (RSS) | The portion of a process's memory resident in physical memory, reported by Linux through [`/proc`](https://docs.kernel.org/filesystems/proc.html) and bounded for campaign verification. |
| Rocq | The [Rocq Prover](https://rocq-prover.org/docs/), an interactive theorem prover used for pure codec and arithmetic theorems. |
| Set | The category whose objects are sets and whose morphisms are total functions. The snapshot laws use this category explicitly. |
| Strongly connected component (SCC) | A maximal directed subgraph in which every vertex reaches every other. The foundational linear-time result is Tarjan, [“Depth-First Search and Linear Graph Algorithms”](https://doi.org/10.1137/0201010). SCC algorithms belong to `libvgraph`, not this crate. |
| Secure Hash Algorithm 256-bit (SHA-256) | The NIST-standardized cryptographic hash used for release-asset and evidence manifests ([FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)). |
| Secure Shell (SSH) | The authenticated protocol whose Ed25519 signatures bind release tags and formal commits to an allowlisted maintainer identity. |
| Software bill of materials (SBOM) | A machine-readable inventory of an artifact and its dependencies. Release assets use CycloneDX 1.5 JSON. |
| Scalable Vector Graphics (SVG) | The W3C vector-image format defined by [SVG 2](https://www.w3.org/TR/SVG2/). Checked-in diagrams are byte-reproducible SVG files. |
| TLA+ | The [Temporal Logic of Actions](https://lamport.azurewebsites.net/tla/tla.html), used to specify the admission state machine and its safety properties. |
| TLC | The explicit-state model checker in the [TLA+ tools](https://github.com/tlaplus/tlaplus), used to enumerate bounded machine states and falsify causal mutants. |
| Verus | The [Verus verifier](https://verus-lang.github.io/verus/guide/), used to connect executable Rust-like arithmetic to proof obligations. |
| Z3 | The [Z3 theorem prover](https://github.com/Z3Prover/z3), used to discharge bit-vector and integer arithmetic obligations and construct boundary witnesses. |

In complexity expressions, $`V`$ is the vertex count, $`E`$ is the edge count, and $`B`$ is the
complete snapshot byte length. All intervals written as `a..b` are half-open: they include `a` and
exclude `b`.
