import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../sealed_bytes.dart';
import '../settings.dart';
import 'prism_http.dart';

class TrackerBureau {
  TrackerBureau();

  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _installPayload;
  Map<String, dynamic>? _deepLinkPayload;
  Map<String, dynamic>? _appOpenPayload;

  final Completer<Map<String, dynamic>> _installReady =
      Completer<Map<String, dynamic>>();
  final Completer<void> _deepLinkReady = Completer<void>();

  bool _started = false;

  /// Fires on every UDL after the first boot POST has finished.
  void Function(Map<String, dynamic> click)? onLateWake;

  bool get hasWake =>
      _deepLinkPayload != null && _deepLinkPayload!.isNotEmpty;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final String devKey = PrismSettings.attributionKey;
    if (devKey.isEmpty) {
      _finishInstall(<String, dynamic>{});
      _finishDeepLink();
      return;
    }

    final AppsFlyerOptions options = AppsFlyerOptions(
      afDevKey: devKey,
      appId: PrismSettings.iosNumericId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );
    final AppsflyerSdk sdk = AppsflyerSdk(options);
    _sdk = sdk;

    sdk.onInstallConversionData((dynamic raw) async {
      final Map<String, dynamic> payload = _flatten(raw);
      final String? status = payload['af_status']?.toString();
      // OneLink click already proves a paid/deferred path —
      // do not stall 9s on a first Organic flicker.
      if (status == 'Organic' && !hasWake) {
        await Future<void>.delayed(
          Duration(seconds: PrismSettings.organicRescueSeconds),
        );
        final Map<String, dynamic>? rescued = await _gcdRescue();
        _installPayload = rescued ?? payload;
      } else {
        _installPayload = payload;
      }
      _finishInstall(_installPayload ?? <String, dynamic>{});
    });

    sdk.onAppOpenAttribution((dynamic raw) {
      _appOpenPayload = _flatten(raw);
    });

    sdk.onDeepLinking((DeepLinkResult result) {
      final Map<String, dynamic>? click = result.deepLink?.clickEvent;
      if (click != null && click.isNotEmpty) {
        _deepLinkPayload = Map<String, dynamic>.from(click);
        assert(() {
          // ignore: avoid_print
          print('[PRISM.BUREAU] udl ${jsonEncode(click)}');
          return true;
        }());
        _finishDeepLink();
        onLateWake?.call(_deepLinkPayload!);
        return;
      }
      _finishDeepLink();
    });

    try {
      await sdk
          .initSdk(
            registerConversionDataCallback: true,
            registerOnAppOpenAttributionCallback: true,
            registerOnDeepLinkingCallback: true,
          )
          .timeout(const Duration(seconds: 8));
      // Consume the Activity intent that opened the app (OneLink).
      recheckDeepLink();
    } catch (_) {
      _finishInstall(<String, dynamic>{});
      _finishDeepLink();
    }
  }

  void recheckDeepLink() {
    try {
      _sdk?.performOnDeepLinking();
    } catch (_) {}
  }

  Future<void> awaitSignals({int? installSeconds}) async {
    final int seconds =
        installSeconds ?? PrismSettings.firstLaunchAwaitSeconds;
    await Future.wait<void>(<Future<void>>[
      _installReady.future.timeout(
        Duration(seconds: seconds),
        onTimeout: () => <String, dynamic>{},
      ),
      _deepLinkReady.future.timeout(
        Duration(seconds: PrismSettings.deepLinkAwaitSeconds),
        onTimeout: () {},
      ),
    ]);
  }

  Future<String?> deviceUid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID().timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> assemble({
    required String locale,
    String? pushToken,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};

    if (_installPayload != null) body.addAll(_installPayload!);
    _deepLinkPayload?.forEach(
        (String k, dynamic v) => body.putIfAbsent(k, () => v));
    _appOpenPayload?.forEach(
        (String k, dynamic v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await deviceUid() ?? '';
    body['bundle_id'] = PrismSettings.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = PrismSettings.storeId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final String project = PrismSettings.messagingProject;
    if (project.isNotEmpty) {
      body['firebase_project_id'] = project;
    }

    assert(() {
      // ignore: avoid_print
      print('[PRISM.BUREAU] assemble ${jsonEncode(body)}');
      return true;
    }());
    return body;
  }

  Future<Map<String, dynamic>?> _gcdRescue() async {
    try {
      final String? uid = await deviceUid();
      if (uid == null) return null;
      final String appRef = Platform.isIOS
          ? PrismSettings.iosNumericId
          : PrismSettings.bundleId;
      final String url = unsealGcdCallUrl(appRef, uid);
      if (url.isEmpty) return null;
      final response = await prismHttp.get(
        Uri.parse(url),
        headers: <String, String>{
          'authorization': 'Bearer ${PrismSettings.attributionKey}',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  void _finishInstall(Map<String, dynamic> data) {
    if (!_installReady.isCompleted) _installReady.complete(data);
  }

  void _finishDeepLink() {
    if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
  }

  static Map<String, dynamic> _flatten(dynamic raw) {
    if (raw is! Map) return <String, dynamic>{};
    final dynamic inner = raw['payload'] ?? raw['data'] ?? raw;
    if (inner is Map) {
      return inner.map(
        (dynamic k, dynamic v) =>
            MapEntry<String, dynamic>(k.toString(), v),
      );
    }
    return <String, dynamic>{};
  }
}
