// ─────────────────────────────────────────────────────────────
// PRISM FFI — Dart ↔ Rust bridge for the sealed-value codec
// ─────────────────────────────────────────────────────────────
// The Rust side (`rust/prism_core`) owns every sealed byte array
// and the FNV→LCG keystream codec. Dart calls `PrismNative.read`
// with an opaque index, Rust unseals the array, wraps it in a
// per-call wire envelope, and returns a freshly allocated buffer
// that Dart decodes and immediately frees.
//
// Wire envelope (matches `rust/prism_core/src/wire.rs`):
//
//   [ nonce(4 LE) | header(4 LE) | body (plain XOR'd with
//       32-byte keystream derived from the nonce) ]
//
//   header == nonce XOR WIRE_KEY_MASK  (0x5A3C17E9)
//
// Loading rules:
//   • Android — DynamicLibrary.open('libprism_core.so').
//   • iOS / desktop — DynamicLibrary.process() so a statically
//     linked symbol (if the Rust lib ever gets vendored into
//     the Flutter engine) still resolves. On platforms without
//     the lib, every call returns `""` so the app degrades to
//     the native game path instead of crashing.
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

// FNV-1a 32-bit parameters — must mirror `cloak.rs`.
const int _fnvOffset = 0x811C9DC5;
const int _fnvPrime = 0x01000193;
const int _lcgMul = 1664525;
const int _lcgAdd = 1013904223;

// Wire constants — must mirror `wire.rs`.
const int _wireHeader = 8;
const int _wireStreamLen = 32;
const int _wireKeyMask = 0x5A3C17E9;

// ─────────────────────────────────────────────────────────────
// Index enum — mirror of `rust/prism_core/src/sealed.rs::Idx`.
// Change in both places together.
// ─────────────────────────────────────────────────────────────
enum SealedIndex {
  endpoint(0),
  gcdBase(1),
  attributionKey(2),
  messagingProject(3),

  uaProduct(10),
  uaLinuxOpen(11),
  uaBuildLabel(12),
  uaBuildClose(13),
  uaEngineLabel(14),
  uaEngineTail(15),
  uaChromeLabel(16),
  uaMobileSafari(17),
  chromeVersion(18),
  webkitVersion(19),
  uaAppIdToken(20),
  uaAppNameToken(21),
  appNameToken(22),

  jsSafeArea(30),
  jsKeyboard(31),
  jsAutoplay(32),
  jsHop(33);

  const SealedIndex(this.raw);
  final int raw;
}

// ─────────────────────────────────────────────────────────────
// FFI signatures
// ─────────────────────────────────────────────────────────────
typedef _PrUNative = ffi.Pointer<ffi.Uint8> Function(
  ffi.Uint32,
  ffi.Pointer<ffi.Size>,
);
typedef _PrUDart = ffi.Pointer<ffi.Uint8> Function(
  int,
  ffi.Pointer<ffi.Size>,
);

typedef _PrFNative = ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _PrFDart = void Function(ffi.Pointer<ffi.Uint8>, int);

abstract final class PrismNative {
  PrismNative._();

  static bool _probed = false;
  static ffi.DynamicLibrary? _lib;
  static _PrUDart? _prU;
  static _PrFDart? _prF;

  /// `true` once the dynamic library has been located and both
  /// FFI symbols resolved. If `false`, every `read` call returns
  /// `""` and the app falls back to the Dart fallback path.
  static bool get isAvailable {
    _ensure();
    return _prU != null && _prF != null;
  }

  static void _ensure() {
    if (_probed) return;
    _probed = true;
    try {
      if (Platform.isAndroid) {
        _lib = ffi.DynamicLibrary.open('libprism_core.so');
      } else if (Platform.isIOS || Platform.isMacOS) {
        _lib = ffi.DynamicLibrary.process();
      } else if (Platform.isLinux) {
        _lib = ffi.DynamicLibrary.open('libprism_core.so');
      } else if (Platform.isWindows) {
        _lib = ffi.DynamicLibrary.open('prism_core.dll');
      }
      final ffi.DynamicLibrary? lib = _lib;
      if (lib == null) return;
      _prU = lib
          .lookup<ffi.NativeFunction<_PrUNative>>('pr_u')
          .asFunction<_PrUDart>();
      _prF = lib
          .lookup<ffi.NativeFunction<_PrFNative>>('pr_f')
          .asFunction<_PrFDart>();
    } catch (_) {
      _lib = null;
      _prU = null;
      _prF = null;
    }
  }

  /// Unseal + decode one entry. Returns `""` on any failure so
  /// callers only need to branch on `isEmpty`.
  static String read(SealedIndex idx) {
    _ensure();
    final _PrUDart? read = _prU;
    final _PrFDart? free = _prF;
    if (read == null || free == null) return '';

    final ffi.Pointer<ffi.Size> outLen = _calloc<ffi.Size>();
    if (outLen == ffi.nullptr) return '';
    ffi.Pointer<ffi.Uint8> ptr = ffi.nullptr;
    try {
      ptr = read(idx.raw, outLen);
      if (ptr == ffi.nullptr) return '';
      final int len = outLen.value;
      if (len < _wireHeader) return '';
      final Uint8List view = ptr.asTypedList(len);
      // Copy out before freeing — the Rust buffer disappears
      // the moment `free` runs.
      final Uint8List envelope = Uint8List.fromList(view);
      return _decodeWire(envelope);
    } catch (_) {
      return '';
    } finally {
      if (ptr != ffi.nullptr) {
        try {
          free(ptr, outLen.value);
        } catch (_) {}
      }
      _calfree(outLen.cast<ffi.Void>());
    }
  }

  // ── wire envelope decoder ──────────────────────────────────
  static String _decodeWire(Uint8List envelope) {
    if (envelope.length < _wireHeader) return '';
    final ByteData bd = ByteData.view(envelope.buffer, envelope.offsetInBytes);
    final int nonce = bd.getUint32(0, Endian.little);
    final int header = bd.getUint32(4, Endian.little);
    if ((nonce ^ _wireKeyMask) & 0xFFFFFFFF != header) return '';
    final Uint8List stream = _streamFromNonce(nonce);
    final int bodyLen = envelope.length - _wireHeader;
    if (bodyLen == 0) return '';
    final Uint8List plain = Uint8List(bodyLen);
    for (int i = 0; i < bodyLen; i++) {
      plain[i] = envelope[_wireHeader + i] ^ stream[i % _wireStreamLen];
    }
    try {
      return utf8.decode(plain);
    } catch (_) {
      return '';
    }
  }

  static Uint8List _streamFromNonce(int nonce) {
    int state = _fnvOffset;
    for (int i = 0; i < 4; i++) {
      final int b = (nonce >> (i * 8)) & 0xFF;
      state ^= b;
      state = (state * _fnvPrime) & 0xFFFFFFFF;
    }
    if (state == 0) state = _fnvPrime;
    final Uint8List out = Uint8List(_wireStreamLen);
    for (int i = 0; i < _wireStreamLen; i++) {
      state = ((state * _lcgMul) + _lcgAdd) & 0xFFFFFFFF;
      out[i] = (state >> 16) & 0xFF;
    }
    return out;
  }
}

// ─────────────────────────────────────────────────────────────
// Minimal replacement for `package:ffi::calloc`. We avoid the
// extra dependency because the whole surface we need here is
// one allocation + free, both via `malloc`/`free` from libc.
// ─────────────────────────────────────────────────────────────
typedef _MallocNative = ffi.Pointer<ffi.Void> Function(ffi.Size);
typedef _MallocDart = ffi.Pointer<ffi.Void> Function(int);

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

final _MallocDart _mallocFn = ffi.DynamicLibrary.process()
    .lookup<ffi.NativeFunction<_MallocNative>>('malloc')
    .asFunction<_MallocDart>();

final _FreeDart _freeFn = ffi.DynamicLibrary.process()
    .lookup<ffi.NativeFunction<_FreeNative>>('free')
    .asFunction<_FreeDart>();

ffi.Pointer<T> _calloc<T extends ffi.NativeType>() {
  // All sealed-value calls allocate a single `Size` cell.
  final int size = ffi.sizeOf<ffi.Size>();
  final ffi.Pointer<ffi.Void> raw = _mallocFn(size);
  if (raw == ffi.nullptr) return ffi.nullptr.cast<T>();
  // Zero the cell so `outLen.value` reads 0 on a Rust early-return.
  raw.cast<ffi.Uint8>().asTypedList(size).fillRange(0, size, 0);
  return raw.cast<T>();
}

void _calfree(ffi.Pointer<ffi.Void> ptr) {
  if (ptr == ffi.nullptr) return;
  _freeFn(ptr);
}
