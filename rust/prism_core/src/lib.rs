// ─────────────────────────────────────────────────────────────
// prism_core — cdylib consumed by the Dart side through FFI.
// ─────────────────────────────────────────────────────────────
// Only two symbols are exported, both intentionally mangled —
// `pr_u` (unseal + wire-wrap) and `pr_f` (free the returned
// buffer). The buffer layout is defined in `wire.rs`; Dart
// decodes it in `lib/prism/native/prism_ffi.dart`.
// ─────────────────────────────────────────────────────────────

#![forbid(unsafe_op_in_unsafe_fn)]
// `extern "C"` fns must stay `#[no_mangle]` for Dart FFI to find
// them; the names themselves are opaque two-letter tokens.

mod cloak;
mod sealed;
mod wire;

use core::ptr;

use sealed::Idx;

/// Unseal the value at `idx`, wire-wrap it, and hand Dart a
/// freshly allocated buffer. The caller MUST invoke `pr_f` with
/// the returned pointer + `*out_len` once the plaintext has been
/// consumed, otherwise the buffer leaks.
///
/// # Safety
/// `out_len` must be a valid, writable `usize*`. The returned
/// pointer is owned by Rust's allocator — do not realloc on
/// the Dart side.
#[no_mangle]
pub unsafe extern "C" fn pr_u(idx: u32, out_len: *mut usize) -> *mut u8 {
    if out_len.is_null() {
        return ptr::null_mut();
    }
    let bytes = match Idx::from_raw(idx) {
        Some(i) => sealed::fetch(i),
        None => Vec::new(),
    };
    let plain = cloak::unseal(&bytes);
    let wrapped = wire::wrap(&plain);
    let mut boxed = wrapped.into_boxed_slice();
    let len = boxed.len();
    let ptr = boxed.as_mut_ptr();
    core::mem::forget(boxed);
    // SAFETY: caller promised `out_len` is non-null and writable.
    unsafe { *out_len = len };
    ptr
}

/// Free a buffer previously returned by `pr_u`.
///
/// # Safety
/// `ptr` must come from a `pr_u` call that returned `len`.
#[no_mangle]
pub unsafe extern "C" fn pr_f(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    // SAFETY: Reconstructs the owned slice we leaked in `pr_u`.
    let _ = unsafe { Box::from_raw(core::slice::from_raw_parts_mut(ptr, len)) };
}

// ─── Self-test (local only; not reachable from FFI) ──────────
#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(idx: Idx) -> String {
        let raw = sealed::fetch(idx);
        let plain = cloak::unseal(&raw);
        String::from_utf8(plain).unwrap()
    }

    #[test]
    fn endpoint_decodes_to_known_url() {
        assert_eq!(
            roundtrip(Idx::Endpoint),
            "https://luminafortune.site/config.php"
        );
    }

    #[test]
    fn gcd_base_decodes() {
        assert!(roundtrip(Idx::GcdBase).starts_with("https://"));
    }

    #[test]
    fn attribution_key_non_empty() {
        assert!(!roundtrip(Idx::AttributionKey).is_empty());
    }

    #[test]
    fn messaging_project_non_empty() {
        assert!(!roundtrip(Idx::MessagingProject).is_empty());
    }

    #[test]
    fn ua_fragments_non_empty() {
        for idx in [
            Idx::UaProduct,
            Idx::UaLinuxOpen,
            Idx::UaBuildLabel,
            Idx::UaEngineLabel,
            Idx::UaEngineTail,
            Idx::UaChromeLabel,
            Idx::UaMobileSafari,
            Idx::ChromeVersion,
            Idx::WebkitVersion,
        ] {
            assert!(!roundtrip(idx).is_empty());
        }
    }

    #[test]
    fn js_payloads_non_empty_and_contain_sentinel() {
        for idx in [Idx::JsSafeArea, Idx::JsKeyboard, Idx::JsAutoplay, Idx::JsHop] {
            let s = roundtrip(idx);
            assert!(!s.is_empty());
            // Each enhancer uses a `window.__lf*` sentinel.
            assert!(s.contains("window.__lf"), "no sentinel in {:?}", idx as u32);
        }
    }

    #[test]
    fn wire_roundtrip() {
        let raw = sealed::fetch(Idx::Endpoint);
        let plain = cloak::unseal(&raw);
        let wrapped = wire::wrap(&plain);
        assert!(wrapped.len() >= 8);
        let nonce = u32::from_le_bytes(wrapped[0..4].try_into().unwrap());
        let header = u32::from_le_bytes(wrapped[4..8].try_into().unwrap());
        assert_eq!(nonce ^ wire::WIRE_KEY_MASK, header);
    }
}
