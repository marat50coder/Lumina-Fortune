import '../diag.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../sealed_bytes.dart';
import '../settings.dart';
import 'prism_http.dart';
import 'push_gate.dart';

class TrackerBureau {
  TrackerBureau();

  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _installPayload;
  Map<String, dynamic>? _deepLinkPayload;
  Map<String, dynamic>? _appOpenPayload;

  // Raw snapshots harvested from the platform channel (Play
  // Install Referrer + launch VIEW intent). Forwarded to the
  // ruling endpoint so the backend can resolve attribution even
  // when AppsFlyer's server-side verdict settled on Organic
  // before Play Services could hand back the referrer.
  String _rawInstallReferrer = '';
  String _rawLaunchUrl = '';

  Completer<Map<String, dynamic>> _installReady =
      Completer<Map<String, dynamic>>();
  Completer<void> _deepLinkReady = Completer<void>();
  // Completed only when the payload has the campaign row the
  // ruling backend actually paints. A thin OneLink echo
  // (`deep_link_value` set, `media_source` / `af_sub*` empty)
  // must not release the first-launch POST.
  final Completer<void> _campaignReady = Completer<void>();

  bool _callbacksBound = false;
  bool _initOk = false;
  Future<void>? _initInFlight;

  /// Fires on every UDL after the first boot POST has finished.
  void Function(Map<String, dynamic> click)? onLateWake;

  bool get hasWake =>
      _deepLinkPayload != null && _deepLinkPayload!.isNotEmpty;

  /// True only after a payload actually proves a paid click.
  /// An unverified `Organic` flicker must not shorten the wait вЂ”
  /// that was locking OneLink installs into the game path.
  bool get hasPaidSignal =>
      _provesPaid(_installPayload) ||
      _provesPaid(_deepLinkPayload) ||
      _provesPaid(_appOpenPayload);

  /// Campaign row the checker paints green: a real `media_source`
  /// together with `campaign` / `af_sub*` / `campaign_id`.
  /// `af_status: Non-organic` alone and a bare `deep_link_value`
  /// do not count вЂ” the offline OneLink boot was posting exactly
  /// that stub, and the backend rendered `sub_id_1 = Organic`.
  bool get hasCampaignFields =>
      _mapHasCampaign(_installPayload) ||
      _mapHasCampaign(_deepLinkPayload) ||
      _mapHasCampaign(_appOpenPayload);

  /// Scans the last UDL payload for anything that decodes to a
  /// full `http(s)://` URL вЂ” checks `deep_link_value`, `af_dp`,
  /// `af_web_dp`, `url`, `deep_link*`, `target`, `landing`, and
  /// their nested payload / data / aps boxes. Returns `null` if
  /// there is no wake or if no key resolves to a URL.
  String? get wakeUrl {
    final Map<String, dynamic>? payload = _deepLinkPayload;
    if (payload == null || payload.isEmpty) return null;
    return pluckGlowUrl(payload);
  }

  /// Idempotent + retryable. First call constructs the SDK and
  /// registers callbacks (works offline вЂ” Play's Install-Referrer
  /// broadcast still lands). Subsequent calls retry `initSdk` if
  /// the previous attempt failed (typical when the first launch
  /// was offline and the user came back online for the retry).
  Future<void> start() async {
    if (_initOk) {
      // A later online retry still needs a fresh UDL read. The
      // deferred OneLink intent is often invisible until the
      // radio is up.
      recheckDeepLink();
      // Rearm the completer so the next `awaitSignals` blocks
      // long enough for AppsFlyer to actually process the
      // referrer server-side (offline first boot completed the
      // completer with a stub Organic payload вЂ” that must not
      // return immediately on retry).
      // A thin Non-organic stamp (af_status flipped, campaign row
      // still empty) must not satisfy the next awaitSignals.
      // Offline boot used to complete the gate on that stub, so
      // the online retry POSTed before AppsFlyer filled af_sub*.
      if (_installReady.isCompleted && !hasCampaignFields) {
        _installReady = Completer<Map<String, dynamic>>();
      }
      return;
    }
    return _initInFlight ??= _boot().whenComplete(() {
      _initInFlight = null;
    });
  }

  Future<void> _boot() async {
    final String devKey = PrismSettings.attributionKey;
    if (devKey.isEmpty) {
      _finishInstall(<String, dynamic>{});
      _finishDeepLink();
      _initOk = true;
      return;
    }

    if (!_callbacksBound) {
      final AppsFlyerOptions options = AppsFlyerOptions(
        afDevKey: devKey,
        appId: PrismSettings.iosNumericId,
        showDebug: kDebugMode,
        timeToWaitForATTUserAuthorization: 10,
      );
      final AppsflyerSdk sdk = AppsflyerSdk(options);
      _sdk = sdk;

      sdk.onInstallConversionData((dynamic raw) async {
        plog(() => '[LF/AF] conversion.raw ${_safeEncode(raw)}');
        final Map<String, dynamic> payload = _flatten(raw);
        plog(() => '[LF/AF] conversion.flat status=${payload['af_status']} '
            'proves=${_provesPaid(payload)} '
            'hasWake=$hasWake '
            'hasPaid=${_provesPaid(_installPayload)} '
            'body=${jsonEncode(payload)}');
        // A later Organic echo must not wipe a OneLink verdict
        // that settleOnline already confirmed. A payload that
        // already carries a campaign is paid, whatever af_status says.
        //
        // Even on an Organic echo, adopt the AF-provided install
        // metadata (install_time, is_first_launch, af_siteid,
        // device fingerprint, etc) when we have no AF payload yet вЂ”
        // stampPaid then flips af_status and scrubs organic-only
        // markers. Dropping the payload here used to leave the
        // first ruling POST without any AF install context, which
        // backend scored as weak-signal and routed as organic.
        if (hasWake || _provesPaid(_installPayload)) {
          if (_provesPaid(payload) && _mapHasCampaign(payload)) {
            _installPayload = payload;
          } else if (_installPayload == null || _installPayload!.isEmpty) {
            _installPayload = payload;
          }
          _stampPaid();
          plog(() => '[LF/AF] conversion в†’ keep-paid '
              'campaign=$hasCampaignFields '
              '${jsonEncode(_installPayload)}');
          // An Organic echo that arrived only because a OneLink
          // wake exists must not close the gate. The deferred
          // conversion with media_source / af_sub* follows a few
          // seconds later, once the radio is actually up.
          if (hasCampaignFields) {
            _finishInstall(_installPayload ?? payload);
          }
          return;
        }
        if (_provesPaid(payload)) {
          _installPayload = payload;
          _stampPaid();
          plog(() => '[LF/AF] conversion в†’ stamp-paid ${jsonEncode(_installPayload)}');
          _finishInstall(payload);
          return;
        }
        final String? status = payload['af_status']?.toString();
        // First callback is often Organic even for a OneLink
        // install. Always give GCD a chance before we trust it.
        // A failed rescue (typical while offline) does NOT lock
        // the verdict вЂ” [settleOnline] queries again once DNS works.
        if (status != null &&
            status.toLowerCase() == 'organic' &&
            !_provesPaid(payload)) {
          plog(() => '[LF/AF] conversion в†’ organic, scheduling GCD in '
              '${PrismSettings.organicRescueSeconds}s');
          await Future<void>.delayed(
            Duration(seconds: PrismSettings.organicRescueSeconds),
          );
          // The deferred Non-organic callback often lands during
          // this pause. Do not let the late GCD result clobber it.
          if (hasCampaignFields) {
            plog(() => '[LF/AF] conversion.gcd skip вЂ” campaign already landed');
            _finishInstall(_installPayload ?? payload);
            return;
          }
          final Map<String, dynamic>? rescued = await _gcdRescue();
          plog(() => '[LF/AF] conversion.gcd rescued=${jsonEncode(rescued)}');
          if (hasCampaignFields) {
            _finishInstall(_installPayload ?? payload);
            return;
          }
          final Map<String, dynamic> flat =
              (rescued != null && rescued.isNotEmpty)
                  ? _flatten(rescued)
                  : payload;
          if (_mapHasCampaign(flat) ||
              _installPayload == null ||
              _installPayload!.isEmpty) {
            _installPayload = flat;
          }
        } else {
          _installPayload = payload;
        }
        plog(() => '[LF/AF] conversion в†’ sealed ${jsonEncode(_installPayload)}');
        _finishInstall(_installPayload ?? <String, dynamic>{});
      });

      sdk.onAppOpenAttribution((dynamic raw) {
        plog(() => '[LF/AF] appOpen.raw ${_safeEncode(raw)}');
        _appOpenPayload = _flatten(raw);
      });

      sdk.onDeepLinking((DeepLinkResult result) {
        plog(() => '[LF/AF] udl status=${result.status} '
            'error=${result.error} '
            'click=${jsonEncode(result.deepLink?.clickEvent)}');
        final Map<String, dynamic>? click = result.deepLink?.clickEvent;
        if (click != null && click.isNotEmpty) {
          _deepLinkPayload = Map<String, dynamic>.from(click);
          _finishDeepLink();
          _signalCampaign();
          onLateWake?.call(_deepLinkPayload!);
          return;
        }
        _finishDeepLink();
      });
      _callbacksBound = true;
    }

    // Rearm completers if a previous offline boot completed them
    // with empty payloads вЂ” otherwise `awaitSignals` on the
    // online retry returns immediately with organic-looking data.
    if (_installReady.isCompleted && !hasCampaignFields) {
      _installReady = Completer<Map<String, dynamic>>();
    }
    if (_deepLinkReady.isCompleted && !hasWake) {
      _deepLinkReady = Completer<void>();
    }
    plog(() => '[LF/AF] initSdk.start devKey.len=${devKey.length}');
    try {
      final dynamic ret = await _sdk!
          .initSdk(
            registerConversionDataCallback: true,
            registerOnAppOpenAttributionCallback: true,
            registerOnDeepLinkingCallback: true,
          )
          .timeout(const Duration(seconds: 8));
      _initOk = true;
      plog(() => '[LF/AF] initSdk.ok result=$ret');
      // Consume the Activity intent that opened the app (OneLink).
      recheckDeepLink();
    } catch (e, s) {
      plog(() => '[LF/AF] initSdk.fail $e\n$s');
      // Leave completers alone. The dispatcher's awaitSignals has
      // its own bounded timeout, and the next start() call (after
      // the user retries) will re-run initSdk on the same SDK.
    }
  }

  static String _safeEncode(Object? raw) {
    try {
      return jsonEncode(raw);
    } catch (_) {
      return raw.toString();
    }
  }

  void recheckDeepLink() {
    try {
      _sdk?.performOnDeepLinking();
      plog(() => '[LF/AF] performOnDeepLinking');
    } catch (e) {
      plog(() => '[LF/AF] performOnDeepLinking.fail $e');
    }
  }

  Future<void> awaitSignals({int? installSeconds}) async {
    final int seconds =
        installSeconds ?? PrismSettings.firstLaunchAwaitSeconds;
    plog(() => '[LF/AF] awaitSignals install=${seconds}s '
        'deep=${PrismSettings.deepLinkAwaitSeconds}s '
        'installReady=${_installReady.isCompleted} '
        'deepReady=${_deepLinkReady.isCompleted}');
    final Stopwatch sw = Stopwatch()..start();
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
    plog(() => '[LF/AF] awaitSignals.done in ${sw.elapsedMilliseconds}ms '
        'hasWake=$hasWake hasPaid=$hasPaidSignal '
        'campaign=$hasCampaignFields '
        'install=${jsonEncode(_installPayload)} '
        'deep=${jsonEncode(_deepLinkPayload)}');
  }

  /// Blocks until [hasCampaignFields] or [seconds] elapse.
  /// Pair with [awaitSignals] on the first launch: the install
  /// gate can close on a thin OneLink echo while `af_sub*` are
  /// still empty, and that is the POST the backend latches.
  Future<void> awaitCampaign({required int seconds}) {
    if (hasCampaignFields) return Future<void>.value();
    plog(() => '[LF/AF] awaitCampaign ${seconds}s');
    return _campaignReady.future.timeout(
      Duration(seconds: seconds),
      onTimeout: () {
        plog(() => '[LF/AF] awaitCampaign.timeout campaign=$hasCampaignFields');
      },
    );
  }

  Future<String?> deviceUid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID().timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  /// Read the launch intent and Play Install Referrer BEFORE
  /// AppsFlyer initSdk fires the conversion POST. The Kotlin side
  /// pre-warms the referrer in `onCreate`; here we wait for that
  /// warm-up to finish so the SDK's server call includes the
  /// referrer and returns a real `Non-organic` verdict.
  Future<void> primeClickSources() async {
    await _absorbLaunchClues();
  }

  /// Call after `awaitSignals` for a bounded backup poll. If the
  /// conversion callback still shows Organic, retry GCD a few
  /// times вЂ” AppsFlyer's server may need extra seconds on a real
  /// offline-then-online install.
  Future<void> settleOnline() async {
    recheckDeepLink();
    await _absorbLaunchClues();
    if (hasCampaignFields) {
      _stampPaid();
      return;
    }
    // Short backup GCD poll (max ~3.5 s total). Longer windows
    // used to idle the warmup screen without actually improving
    // attribution вЂ” the deferred Non-organic callback usually
    // arrives via the SDK before GCD does.
    const List<int> pollDelaysMs = <int>[0, 1500, 2000];
    for (int i = 0; i < pollDelaysMs.length; i++) {
      if (pollDelaysMs[i] > 0) {
        await Future<void>.delayed(Duration(milliseconds: pollDelaysMs[i]));
      }
      final Map<String, dynamic>? rescued = await _gcdRescue();
      if (rescued != null && rescued.isNotEmpty) {
        final Map<String, dynamic> flat = _flatten(rescued);
        plog(() => '[PRISM.BUREAU] gcd#$i ${jsonEncode(flat)}');
        if (_mapHasCampaign(flat)) {
          _installPayload = flat;
          _stampPaid();
          return;
        }
        if (!hasCampaignFields &&
            (_installPayload == null || _installPayload!.isEmpty)) {
          _installPayload = flat;
        }
      }
      recheckDeepLink();
      await _absorbLaunchClues();
      if (hasCampaignFields) {
        _stampPaid();
        return;
      }
    }
  }

  static const MethodChannel _clues =
      MethodChannel('lumina.prism/upload_bridge');

  Future<void> _absorbLaunchClues() async {
    try {
      final Stopwatch sw = Stopwatch()..start();
      final Object? raw = await _clues.invokeMethod<Object>('launch_clues');
      String url = '';
      String referrer = '';
      if (raw is Map) {
        url = _s(raw['url']);
        referrer = _s(raw['referrer']);
      }
      // Remember the latest non-empty raw signals. Backend may
      // use these to resolve attribution even when AppsFlyer's
      // server verdict stuck on Organic.
      if (url.isNotEmpty) _rawLaunchUrl = url;
      if (referrer.isNotEmpty) _rawInstallReferrer = referrer;
      plog(() => '[LF/CLUES] took=${sw.elapsedMilliseconds}ms '
          'raw.type=${raw.runtimeType} url="$url" referrer="$referrer"');
      final Map<String, String> params = <String, String>{};
      String? host;
      if (url.isNotEmpty) {
        final Uri? uri = Uri.tryParse(url);
        if (uri != null) {
          host = uri.host.toLowerCase();
          params.addAll(uri.queryParameters);
        }
      }
      if (referrer.isNotEmpty) {
        try {
          params.addAll(Uri.splitQueryString(referrer));
        } catch (_) {}
      }
      // OneLink host on the VIEW intent IS the paid click, even
      // without any query params attached. That covers the case
      // where the tester opens the app straight from the OneLink
      // preview page.
      final bool onelinkOpened =
          host != null && host.contains('onelink');
      plog(() => '[LF/CLUES] host=$host onelinkOpened=$onelinkOpened '
          'params=${jsonEncode(params)} '
          'clickProvesPaid=${_clickProvesPaid(params)}');
      if (!onelinkOpened && !_clickProvesPaid(params)) return;
      final Map<String, dynamic> click = <String, dynamic>{
        'af_status': 'Non-organic',
      };
      const List<String> keep = <String>[
        'pid',
        'c',
        'af_c',
        'media_source',
        'campaign',
        'campaign_id',
        'deep_link_value',
        'af_dp',
        'af_web_dp',
        'af_tranid',
        'clickid',
      ];
      for (final String key in keep) {
        final String? value = params[key];
        if (value != null && value.isNotEmpty && value != 'null') {
          click[key] = value;
        }
      }
      if (onelinkOpened) {
        click.putIfAbsent('media_source', () => params['pid'] ?? 'onelink');
      }
      final String? campaign = params['c'] ?? params['af_c'];
      if (campaign != null && campaign.isNotEmpty) {
        click.putIfAbsent('campaign', () => campaign);
      }
      _deepLinkPayload = click;
      plog(() => '[LF/CLUES] stamp Non-organic ${jsonEncode(click)}');
      _signalCampaign();
      _finishDeepLink();
    } catch (e, s) {
      plog(() => '[LF/CLUES] fail $e\n$s');
    }
  }

  static String _s(Object? v) {
    if (v == null) return '';
    final String s = v.toString().trim();
    if (s.isEmpty || s == 'null') return '';
    return s;
  }

  bool _clickProvesPaid(Map<String, String> params) {
    final String pid = (params['pid'] ?? '').toLowerCase();
    if (pid.isNotEmpty && pid != 'organic') return true;
    for (final String key in <String>[
      'af_tranid',
      'clickid',
      'deep_link_value',
      'af_dp',
      'af_web_dp',
      'media_source',
      'campaign',
      'campaign_id',
    ]) {
      final String value = (params[key] ?? '').trim().toLowerCase();
      if (value.isEmpty || value == 'organic' || value == 'null') continue;
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> assemble({
    required String locale,
    String? pushToken,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};

    if (_installPayload != null) body.addAll(_installPayload!);
    _mergeCampaign(body, _deepLinkPayload);
    _mergeCampaign(body, _appOpenPayload);
    // A OneLink / deferred click is non-organic even when the
    // first conversion callback still says Organic. The ruling
    // backend keys off this exact field.
    if (hasPaidSignal || hasWake) {
      body['af_status'] = 'Non-organic';
    }

    body['af_id'] = await deviceUid() ?? '';
    body['bundle_id'] = PrismSettings.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = PrismSettings.storeId;
    body['locale'] = locale;

    // Play's organic stub (`utm_medium=organic`) is what the
    // checker paints as sub_id_1 = Organic. A OneLink install
    // that starts offline always receives that stub before
    // AppsFlyer fills the campaign row. Forward the referrer
    // only when it itself proves a paid click.
    if (_rawInstallReferrer.isNotEmpty &&
        !_isOrganicReferrer(_rawInstallReferrer)) {
      body['install_referrer'] = _rawInstallReferrer;
    } else if (_rawInstallReferrer.isNotEmpty) {
      plog(() => '[PRISM.BUREAU] drop organic install_referrer');
    }
    if (_rawLaunchUrl.isNotEmpty) {
      body['launch_intent_url'] = _rawLaunchUrl;
    }

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final String project = PrismSettings.messagingProject;
    if (project.isNotEmpty) {
      body['firebase_project_id'] = project;
    }
    plog(() => '[PRISM.BUREAU] assemble ${jsonEncode(body)}');
    return body;
  }

  Future<Map<String, dynamic>?> _gcdRescue() async {
    try {
      final String? uid = await deviceUid();
      if (uid == null) {
        plog(() => '[LF/GCD] skip вЂ” no uid');
        return null;
      }
      final String appRef = Platform.isIOS
          ? PrismSettings.iosNumericId
          : PrismSettings.bundleId;
      final String url = unsealGcdCallUrl(appRef, uid);
      if (url.isEmpty) {
        plog(() => '[LF/GCD] skip вЂ” url unsealed empty');
        return null;
      }
      final Stopwatch sw = Stopwatch()..start();
      final response = await prismHttp.get(
        Uri.parse(url),
        headers: <String, String>{
          'authorization': 'Bearer ${PrismSettings.attributionKey}',
        },
      ).timeout(const Duration(seconds: 10));
      plog(() => '[LF/GCD] ${response.statusCode} in ${sw.elapsedMilliseconds}ms '
          'body=${response.body}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      plog(() => '[LF/GCD] fail $e');
    }
    return null;
  }

  void _finishInstall(Map<String, dynamic> data) {
    if (!_installReady.isCompleted) _installReady.complete(data);
    // Organic seal must not release the campaign wait. On an
    // offline OneLink boot the first callback is Organic and the
    // real media_source / af_sub* arrive a few seconds later.
    if (hasCampaignFields) _signalCampaign();
  }

  void _signalCampaign() {
    if (!hasCampaignFields || _campaignReady.isCompleted) return;
    plog(() => '[LF/AF] campaign.ready');
    _campaignReady.complete();
  }

  bool _isOrganicReferrer(String referrer) {
    final String lower = referrer.toLowerCase();
    final bool organicMedium = lower.contains('utm_medium=organic') ||
        lower.contains('utm_medium%3dorganic');
    if (!organicMedium) return false;
    try {
      return !_clickProvesPaid(Uri.splitQueryString(referrer));
    } catch (_) {
      return true;
    }
  }

  bool _mapHasCampaign(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return false;
    bool filled(String key) {
      final String value = raw[key]?.toString().trim() ?? '';
      if (value.isEmpty || value == 'null') return false;
      final String lower = value.toLowerCase();
      if (lower == 'organic' || lower == 'onelink') return false;
      return true;
    }

    if (filled('af_sub1') ||
        filled('af_sub2') ||
        filled('campaign_id') ||
        filled('af_c_id')) {
      return true;
    }
    return filled('media_source') && filled('campaign');
  }

  void _finishDeepLink() {
    if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
  }

  void _stampPaid() {
    final Map<String, dynamic> body =
        Map<String, dynamic>.from(_installPayload ?? <String, dynamic>{});
    _mergeCampaign(body, _deepLinkPayload);
    _mergeCampaign(body, _appOpenPayload);
    // Scrub organic-only AppsFlyer markers so backend never sees
    // a contradictory body (e.g. `af_status: Non-organic` while
    // `af_message: "organic install"` still leaked through from
    // the first conversion callback). Backend that keyed off
    // `af_message` would otherwise treat this install as organic
    // and route the gray part with organic campaign params.
    const List<String> organicOnlyMarkers = <String>[
      'af_message',
      'af_messsage', // historical AF typo seen on some SDK versions
      'is_first_launch_organic',
    ];
    for (final String key in organicOnlyMarkers) {
      body.remove(key);
    }
    body['af_status'] = 'Non-organic';
    _installPayload = body;
    _signalCampaign();
  }

  void _mergeCampaign(Map<String, dynamic> into, Map<String, dynamic>? extra) {
    if (extra == null) return;
    extra.forEach((String k, dynamic v) {
      final String incoming = v?.toString().trim() ?? '';
      if (incoming.isEmpty || incoming == 'null') return;
      if (k == 'af_status') {
        if (_isPaidStatus(incoming)) into[k] = v;
        return;
      }
      final String current = into[k]?.toString().trim() ?? '';
      final bool blank = current.isEmpty ||
          current == 'null' ||
          current.toLowerCase() == 'organic';
      if (!into.containsKey(k) || blank) into[k] = v;
    });
  }

  bool _provesPaid(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return false;
    if (_isPaidStatus(raw['af_status']?.toString())) return true;
    const List<String> keys = <String>[
      'media_source',
      'campaign',
      'campaign_id',
      'deep_link_value',
      'af_dp',
      'af_web_dp',
    ];
    for (final String key in keys) {
      final String value = raw[key]?.toString().trim() ?? '';
      if (value.isEmpty) continue;
      if (value.toLowerCase() == 'organic') continue;
      if (value == 'null') continue;
      return true;
    }
    return false;
  }

  bool _isPaidStatus(String? status) {
    if (status == null) return false;
    final String folded = status.toLowerCase().replaceAll('_', '-');
    return folded == 'non-organic' || folded == 'nonorganic';
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
