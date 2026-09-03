use libvgraph::{CsrGraph, DenseId, GraphError};

use crate::{digest::digest_snapshot_with_control, DecodeControl, SnapshotDigest, SnapshotError};

/// Fixed byte count of the version-1 snapshot header.
pub const SNAPSHOT_HEADER_BYTES: usize = 80;
/// Version-1 snapshot magic, including its binary format discriminator.
pub const SNAPSHOT_MAGIC: [u8; 8] = *b"LVGSNP\0\x01";
/// Exact version-1 canonical forward-CSR schema identity.
pub const SNAPSHOT_SCHEMA_ID: [u8; 16] = *b"LVGI-CSR-FWD-V1!";
/// Only supported `(major, minor)` snapshot version.
pub const SNAPSHOT_VERSION: (u16, u16) = (1, 0);

const WORD_BYTES: u64 = 4;
const HEADER_BYTES_U64: u64 = 80;
const CANCELLATION_INTERVAL_WORDS: u64 = 1_024;

#[derive(Debug, Clone, Copy)]
struct AdmittedHeader {
    vertex_count: u32,
    edge_count: u32,
}

/// Opaque identifier for the semantics assigned to dense vertices and edges.
///
/// The codec compares this value exactly. It does not interpret or migrate
/// profiles, which prevents accidental decoding across semantic domains.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(transparent)]
pub struct SemanticProfileId([u8; 32]);

impl SemanticProfileId {
    /// Constructs an identifier from its exact 256-bit representation.
    #[must_use]
    pub const fn new(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    /// Borrows the exact identifier bytes.
    #[must_use]
    pub const fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    /// Returns the exact identifier bytes.
    #[must_use]
    pub const fn into_bytes(self) -> [u8; 32] {
        self.0
    }
}

/// Caller-controlled admission limits for untrusted snapshot bytes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SnapshotLimits {
    /// Maximum declared dense vertices.
    pub max_vertices: u64,
    /// Maximum declared directed edges.
    pub max_edges: u64,
    /// Maximum complete wire bytes.
    pub max_bytes: u64,
}

impl SnapshotLimits {
    /// Returns representation-wide limits. Prefer tighter application limits
    /// at untrusted boundaries.
    #[must_use]
    pub const fn unbounded() -> Self {
        Self {
            max_vertices: u64::MAX,
            max_edges: u64::MAX,
            max_bytes: u64::MAX,
        }
    }
}

/// Returns the exact version-1 wire length for the declared graph counts.
///
/// # Errors
///
/// Returns [`SnapshotError::ArithmeticOverflow`] if the calculation is not
/// representable as `u64`.
pub fn snapshot_wire_len(vertex_count: u32, edge_count: u32) -> Result<u64, SnapshotError> {
    let offset_words = u64::from(vertex_count)
        .checked_add(1)
        .ok_or(SnapshotError::ArithmeticOverflow)?;
    let payload_words = offset_words
        .checked_add(u64::from(edge_count))
        .ok_or(SnapshotError::ArithmeticOverflow)?;
    let payload_bytes = payload_words
        .checked_mul(WORD_BYTES)
        .ok_or(SnapshotError::ArithmeticOverflow)?;
    HEADER_BYTES_U64
        .checked_add(payload_bytes)
        .ok_or(SnapshotError::ArithmeticOverflow)
}

/// Returns the formal decoder's conservative logical-work bound.
///
/// Eight fixed admission operations are followed by two operations per offset
/// word, two per dense node, and three per target word.
///
/// # Errors
///
/// Returns [`SnapshotError::ArithmeticOverflow`] if the calculation is not
/// representable as `u64`.
pub fn required_decode_work(vertex_count: u32, edge_count: u32) -> Result<u64, SnapshotError> {
    let vertices = u64::from(vertex_count);
    let offsets = vertices
        .checked_add(1)
        .ok_or(SnapshotError::ArithmeticOverflow)?;
    8_u64
        .checked_add(
            offsets
                .checked_mul(2)
                .ok_or(SnapshotError::ArithmeticOverflow)?,
        )
        .and_then(|work| work.checked_add(vertices.checked_mul(2)?))
        .and_then(|work| work.checked_add(u64::from(edge_count).checked_mul(3)?))
        .ok_or(SnapshotError::ArithmeticOverflow)
}

/// Encodes a canonical graph as exact version-1 forward-CSR bytes.
///
/// Stable labels and reverse CSR are intentionally omitted. The semantic
/// profile identifies their external interpretation without importing it.
///
/// # Errors
///
/// Returns a structured error if arithmetic overflows or the minimum output
/// capacity cannot be reserved. Safe [`CsrGraph`] construction already
/// establishes canonicality, so encoding does not repeat its linear validator.
pub fn encode_snapshot<K: Ord>(
    graph: &CsrGraph<K>,
    semantic_profile: SemanticProfileId,
) -> Result<Vec<u8>, SnapshotError> {
    let vertex_count =
        u32::try_from(graph.vertex_count()).map_err(|_| SnapshotError::ArithmeticOverflow)?;
    let edge_count =
        u32::try_from(graph.edge_count()).map_err(|_| SnapshotError::ArithmeticOverflow)?;
    let wire_len = snapshot_wire_len(vertex_count, edge_count)?;
    let wire_len_usize =
        usize::try_from(wire_len).map_err(|_| SnapshotError::ArithmeticOverflow)?;
    let payload_len = wire_len
        .checked_sub(HEADER_BYTES_U64)
        .ok_or(SnapshotError::ArithmeticOverflow)?;

    let mut output = reserve_exact("snapshot bytes", wire_len_usize)?;
    output.extend_from_slice(&SNAPSHOT_MAGIC);
    output.extend_from_slice(&SNAPSHOT_SCHEMA_ID);
    output.extend_from_slice(&SNAPSHOT_VERSION.0.to_le_bytes());
    output.extend_from_slice(&SNAPSHOT_VERSION.1.to_le_bytes());
    output.extend_from_slice(&0_u32.to_le_bytes());
    output.extend_from_slice(semantic_profile.as_bytes());
    output.extend_from_slice(&vertex_count.to_le_bytes());
    output.extend_from_slice(&edge_count.to_le_bytes());
    output.extend_from_slice(&payload_len.to_le_bytes());
    for &offset in graph.forward_offsets() {
        output.extend_from_slice(&offset.to_le_bytes());
    }
    for &target in graph.forward_targets() {
        output.extend_from_slice(&target.get().to_le_bytes());
    }
    debug_assert_eq!(output.len(), wire_len_usize);
    Ok(output)
}

/// Decodes exact version-1 bytes under caller-owned admission limits.
///
/// # Errors
///
/// Returns a structured error for incompatible, malformed, over-budget, or
/// allocation-failing input. No partial graph is returned.
pub fn decode_snapshot(
    bytes: &[u8],
    semantic_profile: SemanticProfileId,
    limits: SnapshotLimits,
) -> Result<CsrGraph<DenseId>, SnapshotError> {
    decode_snapshot_with_control(bytes, semantic_profile, limits, DecodeControl::unlimited())
}

/// Decodes exact version-1 bytes with deterministic work and cancellation.
///
/// The header-derived work requirement is admitted before allocation. The
/// cancellation flag is sampled during flat copying and immediately before the
/// return linearization point. The intervening `libvgraph` canonical-import
/// scan is linear and stack-safe but does not accept a cancellation callback.
///
/// # Errors
///
/// Returns a structured error for incompatible, malformed, over-budget,
/// cancelled, or allocation-failing input. No partial graph is returned.
pub fn decode_snapshot_with_control(
    bytes: &[u8],
    semantic_profile: SemanticProfileId,
    limits: SnapshotLimits,
    control: DecodeControl<'_>,
) -> Result<CsrGraph<DenseId>, SnapshotError> {
    decode_admitted(bytes, semantic_profile, limits, control)
}

/// Decodes only if both structure and a domain-separated digest are exact.
///
/// # Errors
///
/// Returns all errors from [`decode_snapshot`] and
/// [`SnapshotError::DigestMismatch`] for stale or foreign bytes. No graph is
/// returned until both checks succeed.
pub fn decode_verified_snapshot(
    bytes: &[u8],
    semantic_profile: SemanticProfileId,
    expected_digest: SnapshotDigest,
    limits: SnapshotLimits,
) -> Result<CsrGraph<DenseId>, SnapshotError> {
    decode_verified_snapshot_with_control(
        bytes,
        semantic_profile,
        expected_digest,
        limits,
        DecodeControl::unlimited(),
    )
}

/// Controlled variant of [`decode_verified_snapshot`].
///
/// # Errors
///
/// Returns a structured admission, cancellation, or digest error without
/// publishing a partial graph.
pub fn decode_verified_snapshot_with_control(
    bytes: &[u8],
    semantic_profile: SemanticProfileId,
    expected_digest: SnapshotDigest,
    limits: SnapshotLimits,
    control: DecodeControl<'_>,
) -> Result<CsrGraph<DenseId>, SnapshotError> {
    admit_byte_limit(bytes, limits)?;
    let actual_digest = digest_snapshot_with_control(bytes, semantic_profile, control)?;
    if actual_digest != expected_digest {
        return Err(SnapshotError::DigestMismatch {
            expected: expected_digest,
            actual: actual_digest,
        });
    }
    decode_admitted(bytes, semantic_profile, limits, control)
}

fn decode_admitted(
    bytes: &[u8],
    expected_profile: SemanticProfileId,
    limits: SnapshotLimits,
    control: DecodeControl<'_>,
) -> Result<CsrGraph<DenseId>, SnapshotError> {
    let header = admit_header(bytes, expected_profile, limits, control)?;
    let vertex_count = header.vertex_count;
    let edge_count = header.edge_count;
    let vertex_len =
        usize::try_from(vertex_count).map_err(|_| SnapshotError::ArithmeticOverflow)?;
    let edge_len = usize::try_from(edge_count).map_err(|_| SnapshotError::ArithmeticOverflow)?;
    let offset_len = vertex_len
        .checked_add(1)
        .ok_or(SnapshotError::ArithmeticOverflow)?;
    let mut offsets = reserve_exact("offsets", offset_len)?;
    let mut targets = reserve_exact("targets", edge_len)?;
    let mut cursor = SNAPSHOT_HEADER_BYTES;
    let mut inspected_words = 0_u64;

    for _ in 0..offset_len {
        offsets.push(read_u32(bytes, &mut cursor)?);
        inspected_words += 1;
        if inspected_words % CANCELLATION_INTERVAL_WORDS == 0 {
            control.check_cancelled(cursor as u64)?;
        }
    }
    for _ in 0..edge_len {
        targets.push(DenseId::from_raw(read_u32(bytes, &mut cursor)?));
        inspected_words += 1;
        if inspected_words % CANCELLATION_INTERVAL_WORDS == 0 {
            control.check_cancelled(cursor as u64)?;
        }
    }
    debug_assert_eq!(cursor, bytes.len());
    control.check_cancelled(cursor as u64)?;

    let mut nodes = reserve_exact("dense nodes", vertex_len)?;
    nodes.extend((0..vertex_count).map(DenseId::from_raw));
    let graph = CsrGraph::try_from_parts(nodes, offsets, targets, None)
        .map_err(snapshot_error_from_graph_error)?;
    control.check_cancelled(cursor as u64)?;
    Ok(graph)
}

fn admit_header(
    bytes: &[u8],
    expected_profile: SemanticProfileId,
    limits: SnapshotLimits,
    control: DecodeControl<'_>,
) -> Result<AdmittedHeader, SnapshotError> {
    control.check_cancelled(0)?;
    let actual_len = admit_byte_limit(bytes, limits)?;
    if bytes.len() < SNAPSHOT_HEADER_BYTES {
        return Err(SnapshotError::TruncatedHeader {
            actual: bytes.len(),
        });
    }
    if bytes[0..8] != SNAPSHOT_MAGIC {
        return Err(SnapshotError::MagicMismatch);
    }
    let schema = copy_array::<16>(&bytes[8..24]);
    if schema != SNAPSHOT_SCHEMA_ID {
        return Err(SnapshotError::SchemaMismatch { found: schema });
    }
    let major = u16::from_le_bytes(copy_array(&bytes[24..26]));
    let minor = u16::from_le_bytes(copy_array(&bytes[26..28]));
    if (major, minor) != SNAPSHOT_VERSION {
        return Err(SnapshotError::VersionMismatch { major, minor });
    }
    let flags = u32::from_le_bytes(copy_array(&bytes[28..32]));
    if flags != 0 {
        return Err(SnapshotError::UnknownFlags { flags });
    }
    let found_profile = SemanticProfileId::new(copy_array(&bytes[32..64]));
    if found_profile != expected_profile {
        return Err(SnapshotError::ProfileMismatch {
            expected: expected_profile,
            found: found_profile,
        });
    }
    let vertex_count = u32::from_le_bytes(copy_array(&bytes[64..68]));
    let edge_count = u32::from_le_bytes(copy_array(&bytes[68..72]));
    let declared_payload = u64::from_le_bytes(copy_array(&bytes[72..80]));
    let expected_wire = snapshot_wire_len(vertex_count, edge_count)?;
    let expected_payload = expected_wire
        .checked_sub(HEADER_BYTES_U64)
        .ok_or(SnapshotError::ArithmeticOverflow)?;
    if declared_payload != expected_payload {
        return Err(SnapshotError::PayloadLengthMismatch {
            expected: expected_payload,
            actual: declared_payload,
        });
    }
    if actual_len != expected_wire {
        return Err(SnapshotError::SnapshotLengthMismatch {
            expected: expected_wire,
            actual: actual_len,
        });
    }
    if u64::from(vertex_count) > limits.max_vertices {
        return Err(SnapshotError::VertexLimitExceeded {
            limit: limits.max_vertices,
            actual: u64::from(vertex_count),
        });
    }
    if u64::from(edge_count) > limits.max_edges {
        return Err(SnapshotError::EdgeLimitExceeded {
            limit: limits.max_edges,
            actual: u64::from(edge_count),
        });
    }
    let required_work = required_decode_work(vertex_count, edge_count)?;
    if required_work > control.work_limit {
        return Err(SnapshotError::WorkLimitExceeded {
            limit: control.work_limit,
            required: required_work,
        });
    }
    control.check_cancelled(0)?;
    Ok(AdmittedHeader {
        vertex_count,
        edge_count,
    })
}

fn admit_byte_limit(bytes: &[u8], limits: SnapshotLimits) -> Result<u64, SnapshotError> {
    let actual = u64::try_from(bytes.len()).map_err(|_| SnapshotError::ArithmeticOverflow)?;
    if actual > limits.max_bytes {
        return Err(SnapshotError::ByteLimitExceeded {
            limit: limits.max_bytes,
            actual,
        });
    }
    Ok(actual)
}

fn snapshot_error_from_graph_error(error: GraphError) -> SnapshotError {
    match error {
        GraphError::OffsetOrigin { actual, .. } => SnapshotError::OffsetOrigin {
            actual: actual.unwrap_or_default(),
        },
        GraphError::OffsetOrder {
            index,
            previous,
            next,
            ..
        } => SnapshotError::OffsetOrder {
            index,
            previous,
            next,
        },
        GraphError::OffsetTerminal {
            expected, actual, ..
        } => match u32::try_from(expected) {
            Ok(expected) => SnapshotError::OffsetTerminal { expected, actual },
            Err(_) => SnapshotError::ArithmeticOverflow,
        },
        GraphError::TargetOutOfRange {
            edge_index,
            target,
            vertex_count,
            ..
        } => SnapshotError::TargetOutOfRange {
            edge_index,
            target,
            vertex_count,
        },
        GraphError::AdjacencyOrder {
            source,
            edge_index,
            previous,
            next,
            ..
        } => SnapshotError::AdjacencyOrder {
            source,
            edge_index,
            previous,
            next,
        },
        other => SnapshotError::CoreGraph(other),
    }
}

fn reserve_exact<T>(collection: &'static str, elements: usize) -> Result<Vec<T>, SnapshotError> {
    let mut values = Vec::new();
    values
        .try_reserve_exact(elements)
        .map_err(|_| SnapshotError::AllocationFailed {
            collection,
            elements,
        })?;
    Ok(values)
}

fn read_u32(bytes: &[u8], cursor: &mut usize) -> Result<u32, SnapshotError> {
    let end = cursor
        .checked_add(4)
        .ok_or(SnapshotError::ArithmeticOverflow)?;
    let word = bytes
        .get(*cursor..end)
        .ok_or(SnapshotError::SnapshotLengthMismatch {
            expected: end as u64,
            actual: bytes.len() as u64,
        })?;
    *cursor = end;
    Ok(u32::from_le_bytes(copy_array(word)))
}

fn copy_array<const N: usize>(bytes: &[u8]) -> [u8; N] {
    let mut output = [0_u8; N];
    output.copy_from_slice(bytes);
    output
}

#[cfg(test)]
mod tests {
    use super::reserve_exact;

    #[test]
    fn minimum_reservation_establishes_at_least_requested_capacity() {
        let values = reserve_exact::<u64>("test values", 17)
            .expect("a small deterministic reservation must succeed");
        assert!(values.is_empty());
        assert!(values.capacity() >= 17);
    }
}
