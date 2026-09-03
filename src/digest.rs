use core::fmt;

use crate::{DecodeControl, SemanticProfileId, SnapshotError, SNAPSHOT_SCHEMA_ID};

const CANCELLATION_CHUNK_BYTES: usize = 64 * 1024;

/// Globally unique BLAKE3 derive-key context for snapshot identity version 1.
pub const DIGEST_CONTEXT: &str =
    "libvgraph-interop 2026-09-02 17:22:31 UTC canonical snapshot digest v1";

/// A domain-separated 256-bit digest of one snapshot invocation.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct SnapshotDigest(blake3::Hash);

impl SnapshotDigest {
    /// Constructs a digest from its exact bytes.
    #[must_use]
    pub const fn new(bytes: [u8; 32]) -> Self {
        Self(blake3::Hash::from_bytes(bytes))
    }

    /// Borrows the exact digest bytes.
    #[must_use]
    pub const fn as_bytes(&self) -> &[u8; 32] {
        self.0.as_bytes()
    }

    /// Returns the exact digest bytes.
    #[must_use]
    pub const fn into_bytes(self) -> [u8; 32] {
        *self.0.as_bytes()
    }
}

impl fmt::Debug for SnapshotDigest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("SnapshotDigest(")?;
        for byte in self.0.as_bytes() {
            write!(formatter, "{byte:02x}")?;
        }
        formatter.write_str(")")
    }
}

/// Digests the exact invocation `(schema, semantic profile, length, bytes)`.
///
/// The snapshot need not be structurally valid. Callers that require both
/// integrity and structural admission should use
/// [`crate::decode_verified_snapshot`].
#[must_use]
pub fn digest_snapshot(bytes: &[u8], semantic_profile: SemanticProfileId) -> SnapshotDigest {
    let mut hasher = digest_hasher(bytes.len(), semantic_profile);
    hasher.update(bytes);
    SnapshotDigest(hasher.finalize())
}

pub(crate) fn digest_snapshot_with_control(
    bytes: &[u8],
    semantic_profile: SemanticProfileId,
    control: DecodeControl<'_>,
) -> Result<SnapshotDigest, SnapshotError> {
    control.check_cancelled(0)?;
    let mut hasher = digest_hasher(bytes.len(), semantic_profile);
    let mut completed_bytes = 0_u64;
    for chunk in bytes.chunks(CANCELLATION_CHUNK_BYTES) {
        hasher.update(chunk);
        completed_bytes = completed_bytes
            .checked_add(u64::try_from(chunk.len()).map_err(|_| SnapshotError::ArithmeticOverflow)?)
            .ok_or(SnapshotError::ArithmeticOverflow)?;
        control.check_cancelled(completed_bytes)?;
    }
    Ok(SnapshotDigest(hasher.finalize()))
}

fn digest_hasher(length: usize, semantic_profile: SemanticProfileId) -> blake3::Hasher {
    let mut hasher = blake3::Hasher::new_derive_key(DIGEST_CONTEXT);
    hasher.update(&SNAPSHOT_SCHEMA_ID);
    hasher.update(semantic_profile.as_bytes());
    hasher.update(&(length as u64).to_le_bytes());
    hasher
}

#[cfg(test)]
mod tests {
    use super::SnapshotDigest;

    #[test]
    fn full_digest_comparison_observes_every_byte() {
        let baseline = SnapshotDigest::new([0; 32]);
        assert_eq!(baseline, SnapshotDigest::new([0; 32]));
        for index in 0..32 {
            let mut changed = [0_u8; 32];
            changed[index] = 1;
            assert_ne!(baseline, SnapshotDigest::new(changed));
        }
    }
}
