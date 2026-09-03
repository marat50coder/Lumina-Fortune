import 'dart:convert';
import 'dart:typed_data';

// ─────────────────────────────────────────────────────────────
// CLOAK — string-hiding codec (FNV-1a seeded LCG keystream)
// ─────────────────────────────────────────────────────────────
// Every "sealed" byte array in this module is unwrapped by
// `unseal()` in this file. The bytes that sit in the compiled
// binary are NEVER the plaintext — they only become the plain
// UTF-8 payload after running through the keystream XOR below.
//
// The template's default codec is a position-XOR family; a
// portfolio-diverse sibling MUST pick a different family. This
// build uses:
//
//   1. FNV-1a fold of the salt into a 32-bit seed. Deterministic
//      per project because the salt bytes are project-unique.
//   2. Linear-congruential (Numerical Recipes constants) advance:
//        s ← (s * 1_664_525 + 1_013_904_223) mod 2^32
//      harvests 8 bits per iteration into the keystream.
//   3. `plain[i] = encoded[i] XOR stream[i % streamLen]`.
//
// No position-mask fold: the shape is deliberately different
// from the position-XOR family so cross-app scanners cannot
// cluster the decoder-loop shape.
// ─────────────────────────────────────────────────────────────

// Salt bytes — project-unique. Rotated per portfolio slot.
const List<int> _saltBytes = <int>[
  0x5D, 0x21, 0xF6, 0xB0,
  0x8E, 0x37, 0x74, 0xC9,
  0x1A, 0x62, 0xAE, 0x0B,
  0xD3, 0x48, 0x91, 0xE5,
  0x2C, 0x7F,
];

// Keystream length. Rotate per project (range 16..48).
const int _streamLen = 29;

// FNV-1a 32-bit parameters.
const int _fnvOffset = 0x811C9DC5;
const int _fnvPrime = 0x01000193;

// Numerical Recipes LCG parameters.
const int _lcgMul = 1664525;
const int _lcgAdd = 1013904223;

Uint8List _buildStream() {
  int state = _fnvOffset;
  for (int i = 0; i < _saltBytes.length; i++) {
    state ^= _saltBytes[i] & 0xFF;
    state = (state * _fnvPrime) & 0xFFFFFFFF;
  }
  if (state == 0) state = _fnvPrime;
  final Uint8List stream = Uint8List(_streamLen);
  for (int i = 0; i < _streamLen; i++) {
    state = (state * _lcgMul + _lcgAdd) & 0xFFFFFFFF;
    stream[i] = (state >> 16) & 0xFF;
  }
  return stream;
}

final Uint8List _stream = _buildStream();

/// Reveals the UTF-8 plaintext behind a sealed byte list.
///
/// Returns `""` for an empty input — that is the state on a fresh
/// template checkout before the operator has packed real values.
/// Callers should check `.isEmpty` on the returned string to
/// decide whether a value has been provisioned.
String unseal(List<int> sealed) {
  if (sealed.isEmpty) return '';
  final Uint8List out = Uint8List(sealed.length);
  for (int i = 0; i < sealed.length; i++) {
    out[i] = (sealed[i] ^ _stream[i % _streamLen]) & 0xFF;
  }
  return utf8.decode(out);
}

/// Seals a plaintext string using the same keystream. Used by the
/// bundled generator (`tool/prism_pack.dart`) and by tests. The
/// runtime app never calls this — the sealed arrays are baked at
/// compile time.
List<int> seal(String plain) {
  if (plain.isEmpty) return const <int>[];
  final List<int> bytes = utf8.encode(plain);
  final List<int> out = List<int>.filled(bytes.length, 0);
  for (int i = 0; i < bytes.length; i++) {
    out[i] = (bytes[i] ^ _stream[i % _streamLen]) & 0xFF;
  }
  return out;
}
