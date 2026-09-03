use core::fmt;

use libvgraph::GraphError;

use crate::{SemanticProfileId, SnapshotDigest, SNAPSHOT_HEADER_BYTES};

/// Structured snapshot encoding, admission, integrity, or control failure.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SnapshotError {
    /// The input ends before the complete fixed-width header.
    TruncatedHeader {
        /// Actual byte length.
        actual: usize,
    },
    /// The eight-byte magic value is not the version-1 snapshot magic.
    MagicMismatch,
    /// The sixteen-byte schema identity is not recognized.
    SchemaMismatch {
        /// Schema bytes found in the header.
        found: [u8; 16],
    },
    /// The major/minor pair is not the exactly supported version.
    VersionMismatch {
        /// Found major version.
        major: u16,
        /// Found minor version.
        minor: u16,
    },
    /// One or more reserved flag bits are set.
    UnknownFlags {
        /// Complete unknown flags word.
        flags: u32,
    },
    /// The embedded semantic profile differs from the expected profile.
    ProfileMismatch {
        /// Caller-required profile.
        expected: SemanticProfileId,
        /// Profile embedded in the snapshot.
        found: SemanticProfileId,
    },
    /// The input byte length exceeds the caller's limit.
    ByteLimitExceeded {
        /// Configured maximum.
        limit: u64,
        /// Actual input length.
        actual: u64,
    },
    /// The vertex count exceeds the caller's limit.
    VertexLimitExceeded {
        /// Configured maximum.
        limit: u64,
        /// Declared vertex count.
        actual: u64,
    },
    /// The edge count exceeds the caller's limit.
    EdgeLimitExceeded {
        /// Configured maximum.
        limit: u64,
        /// Declared edge count.
        actual: u64,
    },
    /// The declared payload length differs from the count-derived length.
    PayloadLengthMismatch {
        /// Count-derived payload length.
        expected: u64,
        /// Declared payload length.
        actual: u64,
    },
    /// The complete input length differs from header plus payload.
    SnapshotLengthMismatch {
        /// Exact required wire length.
        expected: u64,
        /// Actual wire length.
        actual: u64,
    },
    /// A checked length or work calculation overflowed.
    ArithmeticOverflow,
    /// A decoded collection could not reserve its requested minimum bounded capacity.
    AllocationFailed {
        /// Collection whose reservation failed.
        collection: &'static str,
        /// Requested element count.
        elements: usize,
    },
    /// The first CSR offset is not zero.
    OffsetOrigin {
        /// Found first offset.
        actual: u32,
    },
    /// Two adjacent CSR offsets decrease.
    OffsetOrder {
        /// Index of the second offset.
        index: usize,
        /// Previous offset.
        previous: u32,
        /// Decreasing offset.
        next: u32,
    },
    /// The final CSR offset differs from the declared edge count.
    OffsetTerminal {
        /// Declared edge count.
        expected: u32,
        /// Found final offset.
        actual: u32,
    },
    /// A target lies outside the dense vertex domain.
    TargetOutOfRange {
        /// Target-array position.
        edge_index: usize,
        /// Invalid target.
        target: u32,
        /// Dense vertex count.
        vertex_count: u32,
    },
    /// One adjacency slice is not strictly increasing.
    AdjacencyOrder {
        /// Dense source row.
        source: u32,
        /// Position of the second invalid target.
        edge_index: usize,
        /// Previous target.
        previous: u32,
        /// Duplicate or decreasing target.
        next: u32,
    },
    /// The exact decode work exceeds the caller's deterministic budget.
    WorkLimitExceeded {
        /// Configured logical-work limit.
        limit: u64,
        /// Exact logical work required by the admitted header.
        required: u64,
    },
    /// A caller-owned cancellation flag was observed before publication.
    Cancelled {
        /// Input bytes consumed before observing cancellation.
        completed_bytes: u64,
    },
    /// The supplied digest does not match the admitted snapshot invocation.
    DigestMismatch {
        /// Caller-supplied digest.
        expected: SnapshotDigest,
        /// Recomputed digest.
        actual: SnapshotDigest,
    },
    /// An invariant outside the wire-specific error vocabulary failed during final construction.
    CoreGraph(GraphError),
}

impl fmt::Display for SnapshotError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::TruncatedHeader { actual } => write!(
                formatter,
                "snapshot header is truncated: {actual} bytes, expected at least {SNAPSHOT_HEADER_BYTES}"
            ),
            Self::MagicMismatch => formatter.write_str("snapshot magic does not match version 1"),
            Self::SchemaMismatch { found } => {
                write!(formatter, "snapshot schema is unsupported: {found:02x?}")
            }
            Self::VersionMismatch { major, minor } => {
                write!(formatter, "snapshot version {major}.{minor} is unsupported")
            }
            Self::UnknownFlags { flags } => {
                write!(formatter, "snapshot contains unknown flags: 0x{flags:08x}")
            }
            Self::ProfileMismatch { expected, found } => write!(
                formatter,
                "snapshot semantic profile mismatch: expected {expected:?}, found {found:?}"
            ),
            Self::ByteLimitExceeded { limit, actual } => {
                write!(formatter, "snapshot byte length {actual} exceeds limit {limit}")
            }
            Self::VertexLimitExceeded { limit, actual } => {
                write!(formatter, "snapshot vertex count {actual} exceeds limit {limit}")
            }
            Self::EdgeLimitExceeded { limit, actual } => {
                write!(formatter, "snapshot edge count {actual} exceeds limit {limit}")
            }
            Self::PayloadLengthMismatch { expected, actual } => write!(
                formatter,
                "snapshot payload length is {actual}, expected {expected} from counts"
            ),
            Self::SnapshotLengthMismatch { expected, actual } => write!(
                formatter,
                "snapshot wire length is {actual}, expected exactly {expected}"
            ),
            Self::ArithmeticOverflow => {
                formatter.write_str("snapshot length or work arithmetic overflowed")
            }
            Self::AllocationFailed {
                collection,
                elements,
            } => write!(
                formatter,
                "failed to reserve {elements} elements for decoded {collection}"
            ),
            Self::OffsetOrigin { actual } => {
                write!(formatter, "forward offsets must begin at zero, found {actual}")
            }
            Self::OffsetOrder {
                index,
                previous,
                next,
            } => write!(
                formatter,
                "forward offsets decrease at {index}: {previous} then {next}"
            ),
            Self::OffsetTerminal { expected, actual } => write!(
                formatter,
                "forward terminal offset is {actual}, expected {expected}"
            ),
            Self::TargetOutOfRange {
                edge_index,
                target,
                vertex_count,
            } => write!(
                formatter,
                "forward target {target} at {edge_index} is outside 0..{vertex_count}"
            ),
            Self::AdjacencyOrder {
                source,
                edge_index,
                previous,
                next,
            } => write!(
                formatter,
                "forward adjacency for {source} is not strictly ordered at {edge_index}: {previous} then {next}"
            ),
            Self::WorkLimitExceeded { limit, required } => write!(
                formatter,
                "snapshot decode requires {required} logical operations, exceeding limit {limit}"
            ),
            Self::Cancelled { completed_bytes } => write!(
                formatter,
                "snapshot decode cancelled after consuming {completed_bytes} input bytes"
            ),
            Self::DigestMismatch { expected, actual } => write!(
                formatter,
                "snapshot digest mismatch: expected {expected:?}, computed {actual:?}"
            ),
            Self::CoreGraph(error) => error.fmt(formatter),
        }
    }
}

impl std::error::Error for SnapshotError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::CoreGraph(error) => Some(error),
            _ => None,
        }
    }
}

impl From<GraphError> for SnapshotError {
    fn from(error: GraphError) -> Self {
        Self::CoreGraph(error)
    }
}
