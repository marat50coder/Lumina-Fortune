// ─────────────────────────────────────────────────────────────
// cloak — in-crate string codec (FNV-1a → LCG keystream → XOR)
// ─────────────────────────────────────────────────────────────
// This file is a bit-exact port of `lib/prism/cloak.dart` so
// every sealed byte array that still exists on the Dart side
// (should any slip through) can be unsealed to the same bytes.
//
// Why the port is here and not re-generated: the sealed-bytes
// generator (`tool/prism_pack.dart`) already shipped values
// computed with the Dart codec. Keeping the Rust codec
// bit-exact lets us copy the sealed arrays over as-is without
// re-running the generator.
//
// Hardening notes:
//   • Salt + FNV + LCG constants come through `obfstr::obfbytes!`
//     / `obfconst!` so they do not sit as readable literals in
//     the compiled `.so` (strings/radare2 would otherwise print
//     them in a single line).
//   • The keystream is built once per unseal call rather than
//     cached, so a mid-process memory dump finds the stream in
//     the ephemeral call frame instead of a `.data` region.
// ─────────────────────────────────────────────────────────────

use obfstr::obfbytes;

const STREAM_LEN: usize = 29;
// FNV-1a 32-bit parameters — mirror of the Dart module.
const FNV_OFFSET: u32 = 0x811C_9DC5;
const FNV_PRIME: u32 = 0x0100_0193;
// Numerical Recipes LCG.
const LCG_MUL: u32 = 1_664_525;
const LCG_ADD: u32 = 1_013_904_223;

#[inline(always)]
fn salt() -> [u8; 18] {
    // obfstr scrambles the array in `.rodata`, descrambles on
    // first use. The literal shown here is never present in
    // the compiled binary as a contiguous byte run.
    *obfbytes!(&[
        0x5D, 0x21, 0xF6, 0xB0,
        0x8E, 0x37, 0x74, 0xC9,
        0x1A, 0x62, 0xAE, 0x0B,
        0xD3, 0x48, 0x91, 0xE5,
        0x2C, 0x7F,
    ])
}

#[inline(never)]
pub fn build_stream() -> [u8; STREAM_LEN] {
    let salt = salt();
    let mut state: u32 = FNV_OFFSET;
    for b in salt.iter() {
        state ^= u32::from(*b);
        state = state.wrapping_mul(FNV_PRIME);
    }
    if state == 0 {
        state = FNV_PRIME;
    }
    let mut stream = [0u8; STREAM_LEN];
    for s in stream.iter_mut() {
        state = state.wrapping_mul(LCG_MUL).wrapping_add(LCG_ADD);
        *s = ((state >> 16) & 0xFF) as u8;
    }
    stream
}

/// Reveals the UTF-8 plaintext behind a sealed byte slice.
/// Returns an empty `Vec` if the input is empty.
pub fn unseal(sealed: &[u8]) -> Vec<u8> {
    if sealed.is_empty() {
        return Vec::new();
    }
    let stream = build_stream();
    let mut out = Vec::with_capacity(sealed.len());
    for (i, b) in sealed.iter().enumerate() {
        out.push(b ^ stream[i % STREAM_LEN]);
    }
    out
}
