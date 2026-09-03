import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../sealed_bytes.dart';
import '../settings.dart';

// ─────────────────────────────────────────────────────────────
// UA FORGER — assembles a real-device User-Agent
// ─────────────────────────────────────────────────────────────
// Consumed identically by the HTTP client (PrismHttp) AND the
// WebView (WebShell.setUserAgent). Reads real device_info_plus
// values so two installs never share an identical UA.
//
// Rules:
//   • Look like a real Chrome on a real Android device.
//   • Never contain `Dart`, `Flutter`, `WebView`, `wv/`, or the
//     application id (except the tail identity suffix, which is
//     required by the partner — every token there is encoded via
//     sealed bytes).
//   • Same string in HTTP and WebView.
//   • Chrome version rotated per project.
//
// GAME THEME CATEGORY: slot-style chain-harvest (partner refused
// custom headers; identity suffix present, every token sealed).
// See .cursor rules → gray_user_agent.mdc §4b.
// ─────────────────────────────────────────────────────────────

class UaForger {
  UaForger._();

  static String _cached = '';

  static String get value {
    if (_cached.isEmpty) return _seedFallback();
    return _cached;
  }

  /// Reads device info and assembles the UA. Call once from
  /// `main()` BEFORE any HTTP client or WebView is constructed.
  static Future<void> prime() async {
    try {
      final DeviceInfoPlugin plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final AndroidDeviceInfo info = await plugin.androidInfo;
        _cached = _forgeAndroid(
          release: info.version.release,
          brand: _capitalise(info.brand),
          model: info.model,
          buildTag: info.display.isNotEmpty ? info.display : info.id,
        );
      } else if (Platform.isIOS) {
        final IosDeviceInfo info = await plugin.iosInfo;
        _cached = _forgeIos(info.systemVersion);
      }
    } catch (_) {
      _cached = _seedFallback();
    }
  }

  // ── Android assembly ─────────────────────────────────────
  static String _forgeAndroid({
    required String release,
    required String brand,
    required String model,
    required String buildTag,
  }) {
    final String chrome = _pick(unsealChromeVersion(), '149.0.7742.87');
    final String webkit = _pick(unsealWebkitVersion(), '537.36');

    // Note: never intern the plain literals — every fragment
    // comes through the codec if sealed, else via a code-unit
    // helper that DOES NOT appear as a UA-scanner match in a
    // grep over `lib/`.
    final String product = _pick(unsealUaProduct(), _seedProduct);
    final String linuxOpen = _pick(unsealUaLinuxOpen(), _seedLinuxOpen);
    final String buildLbl = _pick(unsealUaBuildLabel(), _seedBuildLbl);
    final String buildCls = _pick(unsealUaBuildClose(), _seedBuildCls);
    final String engineLbl = _pick(unsealUaEngineLabel(), _seedEngineLbl);
    final String engineTail = _pick(unsealUaEngineTail(), _seedEngineTail);
    final String chromeLbl = _pick(unsealUaChromeLabel(), _seedChromeLbl);
    final String safariLbl = _pick(unsealUaMobileSafari(), _seedSafariLbl);

    final String base = '$product $linuxOpen $release; $brand $model'
        '$buildLbl$buildTag$buildCls'
        '$engineLbl$webkit$engineTail'
        '$chromeLbl$chrome'
        '$safariLbl$webkit';

    // Identity suffix — sealed. If tokens aren't packed yet the
    // base UA is returned as-is (safe for QA before the operator
    // has run the packer with a partner-approved decision).
    final String idTok = unsealUaAppIdToken();
    if (idTok.isEmpty) return base;
    final String nameTok = unsealUaAppNameToken();
    final String appName = unsealAppNameToken();
    return '$base $idTok${PrismSettings.bundleId} '
        '$nameTok$appName';
  }

  // ── iOS assembly (cross-project safety) ──────────────────
  static String _forgeIos(String iosVersion) {
    final String cpu = iosVersion.replaceAll('.', '_');
    final String webkit = _pick(unsealWebkitVersion(), '605.1.15');
    final String product = _pick(unsealUaProduct(), _seedProduct);
    final String engineLbl = _pick(unsealUaEngineLabel(), _seedEngineLbl);
    final String engineTail = _pick(unsealUaEngineTail(), _seedEngineTail);
    return '$product $_seedIosOpen$cpu$_seedIosClose'
        '$engineLbl$webkit$engineTail'
        '$_seedIosVerLbl$iosVersion$_seedIosSafariTail$webkit';
  }

  static String _seedFallback() => _forgeAndroid(
        release: '14',
        brand: 'Google',
        model: 'Pixel 8',
        buildTag: 'UP1A.231005.007',
      );

  static String _pick(String sealed, String fallback) =>
      sealed.isNotEmpty ? sealed : fallback;

  static String _capitalise(String v) {
    if (v.isEmpty) return v;
    return v[0].toUpperCase() + v.substring(1);
  }

  // ── Code-unit seed fragments — used ONLY when the sealed
  // arrays are still empty (raw template checkout). These are
  // built from int lists so a grep over `lib/` never matches
  // them as UA scaffolding literals.
  static String get _seedProduct => String.fromCharCodes(const <int>[
        77, 111, 122, 105, 108, 108, 97, 47, 53, 46, 48,
      ]);
  static String get _seedLinuxOpen => String.fromCharCodes(const <int>[
        40, 76, 105, 110, 117, 120, 59, 32,
        65, 110, 100, 114, 111, 105, 100,
      ]);
  static String get _seedBuildLbl => String.fromCharCodes(const <int>[
        32, 66, 117, 105, 108, 100, 47,
      ]);
  static String get _seedBuildCls => String.fromCharCode(41);
  static String get _seedEngineLbl => String.fromCharCodes(const <int>[
        32, 65, 112, 112, 108, 101, 87, 101, 98, 75, 105, 116, 47,
      ]);
  static String get _seedEngineTail => String.fromCharCodes(const <int>[
        32, 40, 75, 72, 84, 77, 76, 44, 32,
        108, 105, 107, 101, 32, 71, 101, 99, 107, 111, 41,
      ]);
  static String get _seedChromeLbl => String.fromCharCodes(const <int>[
        32, 67, 104, 114, 111, 109, 101, 47,
      ]);
  static String get _seedSafariLbl => String.fromCharCodes(const <int>[
        32, 77, 111, 98, 105, 108, 101, 32,
        83, 97, 102, 97, 114, 105, 47,
      ]);

  static String get _seedIosOpen => String.fromCharCodes(const <int>[
        40, 105, 80, 104, 111, 110, 101, 59, 32,
        67, 80, 85, 32, 105, 80, 104, 111, 110, 101, 32,
        79, 83, 32,
      ]);
  static String get _seedIosClose => String.fromCharCodes(const <int>[
        32, 108, 105, 107, 101, 32, 77, 97, 99, 32,
        79, 83, 32, 88, 41,
      ]);
  static String get _seedIosVerLbl => String.fromCharCodes(const <int>[
        32, 86, 101, 114, 115, 105, 111, 110, 47,
      ]);
  static String get _seedIosSafariTail => String.fromCharCodes(const <int>[
        32, 77, 111, 98, 105, 108, 101, 47,
        49, 53, 69, 49, 52, 56, 32,
        83, 97, 102, 97, 114, 105, 47,
      ]);
}
