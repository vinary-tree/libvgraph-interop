//! Canonical, bounded, stack-safe interchange for [`libvgraph`].
//!
//! The crate owns one exact flat wire format, semantic-profile binding, and a
//! domain-separated BLAKE3 digest. It deliberately leaves graph algorithms,
//! stable labels, domain payloads, and provenance in their owning layers.

#![doc = include_str!("../README.md")]
#![doc = include_str!("../docs/usage/rust-api.md")]
#![forbid(unsafe_code)]
#![deny(missing_docs)]

mod control;
mod digest;
mod error;
mod wire;

pub use control::DecodeControl;
pub use digest::{digest_snapshot, SnapshotDigest, DIGEST_CONTEXT};
pub use error::SnapshotError;
pub use wire::{
    decode_snapshot, decode_snapshot_with_control, decode_verified_snapshot,
    decode_verified_snapshot_with_control, encode_snapshot, required_decode_work,
    snapshot_wire_len, SemanticProfileId, SnapshotLimits, SNAPSHOT_HEADER_BYTES, SNAPSHOT_MAGIC,
    SNAPSHOT_SCHEMA_ID, SNAPSHOT_VERSION,
};
