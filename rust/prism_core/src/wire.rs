// ─────────────────────────────────────────────────────────────
// wire — ephemeral per-call obfuscation of the Rust→Dart buffer
// ─────────────────────────────────────────────────────────────
// Dart and Rust share the same process so a true cipher between
// them is pointless — they both see the full address space. The
// goal here is weaker but still useful: do NOT let the plaintext
// unseal result sit in a predictable buffer that a `cat
// /proc/<pid>/maps` + `dd` + `strings` dump would catch.
//
// Shape of the returned buffer:
//
//   [ nonce(4) | key_header(4) | body (unseal_len bytes) ]
//
// `nonce`      — 4 random bytes seeded from the system clock +
//                process-local counter.
// `key_header` — nonce XOR'd with a constant from `cloak.rs`.
//                Lets Dart detect a tampered buffer without
//                adding a true MAC (unnecessary in-process).
// `body`       — plaintext XOR'd with a 32-byte stream derived
//                from the nonce via the same FNV→LCG chain used
//                for the real cloak codec (same math, different
//                seed).
//
// Dart undoes this inside `_decodeWire` in prism_ffi.dart.
// ─────────────────────────────────────────────────────────────

use core::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::cloak;

const WIRE_HEADER: usize = 8;
const WIRE_STREAM_LEN: usize = 32;

// FNV-1a parameters (shared with cloak).
const FNV_OFFSET: u32 = 0x811C_9DC5;
const FNV_PRIME: u32 = 0x0100_0193;
const LCG_MUL: u32 = 1_664_525;
const LCG_ADD: u32 = 1_013_904_223;
// Fixed cross-check constant woven into the key header. MUST
// match `_wireKeyMask` in `lib/prism/native/prism_ffi.dart`.
pub const WIRE_KEY_MASK: u32 = 0x5A3C_17E9;

static COUNTER: AtomicU64 = AtomicU64::new(0x9E37_79B9_7F4A_7C15);

fn next_nonce() -> [u8; 4] {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0);
    let tick = COUNTER.fetch_add(0x9E37_79B9_7F4A_7C15, Ordering::Relaxed);
    let mix = (now ^ tick ^ tick.rotate_left(27)) as u32;
    mix.to_le_bytes()
}

fn stream_from_nonce(nonce: [u8; 4]) -> [u8; WIRE_STREAM_LEN] {
    let mut state: u32 = FNV_OFFSET;
    for b in nonce.iter() {
        state ^= u32::from(*b);
        state = state.wrapping_mul(FNV_PRIME);
    }
    if state == 0 {
        state = FNV_PRIME;
    }
    let mut out = [0u8; WIRE_STREAM_LEN];
    for s in out.iter_mut() {
        state = state.wrapping_mul(LCG_MUL).wrapping_add(LCG_ADD);
        *s = ((state >> 16) & 0xFF) as u8;
    }
    out
}

/// Wraps the already-unsealed plaintext into the wire envelope
/// described at the top of this file. Returns the full buffer.
pub fn wrap(plain: &[u8]) -> Vec<u8> {
    let nonce = next_nonce();
    let stream = stream_from_nonce(nonce);

    let mut buf = Vec::with_capacity(WIRE_HEADER + plain.len());
    buf.extend_from_slice(&nonce);
    let header = u32::from_le_bytes(nonce) ^ WIRE_KEY_MASK;
    buf.extend_from_slice(&header.to_le_bytes());
    for (i, byte) in plain.iter().enumerate() {
        buf.push(byte ^ stream[i % WIRE_STREAM_LEN]);
    }
    buf
}

// `cloak` is referenced here only to keep the symbol graph
// stable — the real callers live in `lib.rs`.
#[allow(dead_code)]
fn _link_cloak_marker() {
    let _ = cloak::build_stream();
}
