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

  // ── Timing constants (rotated per project) ──────────────────
  // Numeric literals survive `--obfuscate`, so every one here is
  // a distinct value from other portfolio siblings. See the
  // ranges documented in .cursor rules → relay_forge §1.

  /// Snooze after a "Skip" tap on the push-invite screen.
  /// Range 172_800..604_800. Picked: 2 d 22 h — QA reported the
  /// previous 3 d 4 h value surfaced the invite on day 4 instead
  /// of day 3, so this shaves 6 h to guarantee a same-third-day
  /// re-prompt across time zones (2*86_400 + 22*3_600 = 252_000).
  static const int inviteSnoozeSeconds = 252_000;

  /// Delay before rescuing an initial `af_status: Organic`.
  /// Range 4..12 s.
  static const int organicRescueSeconds = 9;

  /// POST timeout for the ruling endpoint. Range 10..25 s.
  static const int rulingTimeoutSeconds = 19;

  /// First-launch install-conversion wait. Range 20..40 s.
  static const int firstLaunchAwaitSeconds = 31;

  /// Returning-launch install-conversion wait. Range 3..10 s.
  static const int returningAwaitSeconds = 7;

  /// UDL / deep-link wait. Range 3..8 s.
  static const int deepLinkAwaitSeconds = 5;

  /// DNS probe timeout. Keep >= 4 s (VPN tunnels are slow).
  static const int dnsProbeSeconds = 7;

  /// Debounce before a live connectivity drop routes to no-link.
  /// Range 500..1_200 ms.
  static const int dropDebounceMs = 940;

  /// Bounded main-frame redirect-loop retries. Keep small.
  static const int redirectRetryBudget = 3;

  /// Freshness window of the cached destination URL. 3..14 days.
  static const int cacheLifetimeSeconds = 6 * 24 * 60 * 60;

  // ── Resolved (sealed) endpoints & credentials ───────────────
  static String get rulingEndpoint => unsealEndpoint();
  static String get attributionKey => unsealAttributionKey();
  static String get messagingProject => unsealMessagingProject();

  static String get storeId {
    if (iosNumericId.isNotEmpty) return 'id$iosNumericId';
    return storeToken;
  }

  /// The gray gate stays disabled — every install lands directly
  /// in the native game — until all three sealed values decode
  /// non-empty. This lets QA smoke-test the white part before the
  /// operator has finished packing credentials.
  static bool get gateReady =>
      rulingEndpoint.isNotEmpty &&
      attributionKey.isNotEmpty &&
      messagingProject.isNotEmpty;
}
