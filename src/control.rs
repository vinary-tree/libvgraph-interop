use std::sync::atomic::{AtomicBool, Ordering};

use crate::SnapshotError;

/// Deterministic work and cooperative-cancellation controls for decoding.
///
/// The work limit is checked from the admitted header before allocation. The
/// optional flag carries cancellation only; its relaxed load does not
/// synchronize any other caller-owned data. Once a caller requests atomic
/// cancellation, it must leave the flag set until the operation returns.
#[derive(Debug, Clone, Copy)]
pub struct DecodeControl<'a> {
    pub(crate) work_limit: u64,
    cancellation: Option<&'a AtomicBool>,
    cancel_after_bytes: Option<u64>,
}

impl DecodeControl<'static> {
    /// Returns the largest logical-work budget with no cancellation flag.
    #[must_use]
    pub const fn unlimited() -> Self {
        Self {
            work_limit: u64::MAX,
            cancellation: None,
            cancel_after_bytes: None,
        }
    }
}

impl<'a> DecodeControl<'a> {
    /// Creates a decoder control with an exact logical-work limit.
    #[must_use]
    pub const fn with_work_limit(work_limit: u64) -> Self {
        Self {
            work_limit,
            cancellation: None,
            cancel_after_bytes: None,
        }
    }

    /// Adds a caller-owned atomic cancellation flag.
    #[must_use]
    pub const fn with_cancellation(mut self, cancellation: &'a AtomicBool) -> Self {
        self.cancellation = Some(cancellation);
        self
    }

    /// Adds a deterministic cancellation threshold for one scanning phase.
    ///
    /// A checkpoint whose completed-byte position is greater than or equal to
    /// `threshold` returns [`SnapshotError::Cancelled`]. Verified decoding
    /// applies the threshold independently to its digest and structural scans.
    #[must_use]
    pub const fn with_cancel_after_bytes(mut self, threshold: u64) -> Self {
        self.cancel_after_bytes = Some(threshold);
        self
    }

    /// Returns the configured logical-work limit.
    #[must_use]
    pub const fn work_limit(self) -> u64 {
        self.work_limit
    }

    #[inline]
    pub(crate) fn check_cancelled(self, completed_bytes: u64) -> Result<(), SnapshotError> {
        if self
            .cancel_after_bytes
            .is_some_and(|threshold| completed_bytes >= threshold)
            || self
                .cancellation
                .is_some_and(|flag| flag.load(Ordering::Relaxed))
        {
            return Err(SnapshotError::Cancelled { completed_bytes });
        }
        Ok(())
    }
}
