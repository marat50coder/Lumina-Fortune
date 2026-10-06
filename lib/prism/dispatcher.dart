import 'dart:async';
import 'dart:io';

import 'net/cold_intent.dart';
import 'net/link_gauge.dart';
import 'net/local_vault.dart';
import 'net/push_gate.dart';
import 'net/ruling_endpoint.dart';
import 'net/tracker_bureau.dart';
import 'routing.dart';
import 'settings.dart';

// ─────────────────────────────────────────────────────────────
// DISPATCHER — the single boot-decision entry point
// ─────────────────────────────────────────────────────────────
// One method: `resolve(onProgress)` returns a sealed [PrismRoute].
// The warmup screen destructures via `switch` and only there
// decides which route to push. No routing logic anywhere else.
//
// Branches by persisted [RouteMemo]:
//
//   fresh (first launch)
//     ├─ no adapter        → NoLinkRoute(canFallToGame: false)
//     ├─ DNS unreachable   → NoLinkRoute(canFallToGame: false)
//     ├─ ruling approved   → save web    → ShellRoute(url)
//     └─ ruling rejected   → save native → NativeRoute
//
//   webShell (was in the shell)
//     ├─ no adapter                    → NoLinkRoute(canFallToGame: false)
//     ├─ cold-tap URL                  → ShellRoute(url, coldTap: true)
//     ├─ fresh cached URL              → ShellRoute(cached)
//     ├─ ruling approved               → ShellRoute(fresh)
//     ├─ ruling rejected but cache OK  → ShellRoute(cached)
//     └─ otherwise                     → NoLinkRoute(canFallToGame: false)
//
//   nativeGame (was in the white game)
//     ├─ no adapter        → NativeRoute (never blocks the game)
//     ├─ ruling approved   → save web → ShellRoute(url)
//     └─ ruling rejected   → NativeRoute
//
// Concurrent boots are de-duplicated — the in-flight future is
// cached so two synchronous `resolve()` calls never trigger two
// ruling POSTs. Cache clears on completion so a retry from the
// no-link screen replays the full pipeline.
// ─────────────────────────────────────────────────────────────

class PrismDispatcher {
  PrismDispatcher({
    required this.vault,
    required this.gauge,
    required this.bureau,
    required this.endpoint,
    required this.pushGate,
  });

  final LocalVault vault;
  final LinkGauge gauge;
  final TrackerBureau bureau;
  final RulingEndpoint endpoint;
  final PushGate pushGate;

  Future<PrismRoute>? _inFlight;

  void Function(String url)? onGrayReady;

  Future<PrismRoute> resolve({void Function(double)? onProgress}) {
    return _inFlight ??= _resolve(onProgress ?? (_) {}).whenComplete(() {
      _inFlight = null;
      bureau.onLateWake = _onLateWake;
      // Only wire the FCM-token-rotate hook AFTER the first ruling
      // POST has been emitted. If we attach it before `_resolve`
      // runs, the very first `_fetchToken()` (unawaited inside
      // `pushGate.ignite()`) races the AppsFlyer conversion
      // callback and fires a premature POST with empty campaign /
      // media_source / af_sub* — the backend latches that stub
      // as the install's "ground truth" and the user sees the
      // gray part open with organic attribution even though the
      // click was a real OneLink. The second (correct) POST that
      // follows cannot overwrite that verdict server-side.
      pushGate.onTokenRotate = _refreshOnTokenRotate;
    });
  }

  Future<PrismRoute> _resolve(void Function(double) progress) async {
    // ignore: avoid_print
    print('[LF/DISP] resolve.begin gateReady=${PrismSettings.gateReady} '
        'route=${vault.route}');
    if (!PrismSettings.gateReady) {
      progress(1);
      return const NativeRoute();
    }

    // Park the current tap inside ignite first. Reading the vault
    // before that would replay a leftover URL from another push.
    try {
      await pushGate.ignite().timeout(const Duration(seconds: 3));
    } catch (_) {}
    final PrismRoute? wake = await _consumeTap();
    if (wake != null) {
      unawaited(_backgroundRefresh());
      progress(1);
      return wake;
    }

    progress(0.18);
    return switch (vault.route) {
      RouteMemo.fresh => _resolveFirstLaunch(progress),
      RouteMemo.webShell => _resolveReturningShell(progress),
      RouteMemo.nativeGame => _resolveReturningNative(progress),
    };
  }

  Future<PrismRoute> _resolveFirstLaunch(
    void Function(double) progress,
  ) async {
    // ignore: avoid_print
    print('[LF/DISP] firstLaunch.enter');
    if (!await _adapterUp()) {
      // ignore: avoid_print
      print('[LF/DISP] firstLaunch → NoLink (adapter down)');
      return const NoLinkRoute(canFallToGame: false);
    }
    progress(0.32);
    // `pushGate.ignite()` is idempotent (see push_gate.dart) — a
    // second call here was a leftover from an earlier branch and
    // just added timeout slack.
    final bool online = await _online();
    // ignore: avoid_print
    print('[LF/DISP] firstLaunch.online=$online');
    if (!online) {
      // ignore: avoid_print
      print('[LF/DISP] firstLaunch → NoLink (offline)');
      return const NoLinkRoute(canFallToGame: false);
    }
    progress(0.48);
    // Give the Play Install Referrer service a beat to reply.
    // The Kotlin side has been warming it since onCreate — on a
    // normal online install it is cached already and the call
    // returns almost instantly. Start AppsFlyer in parallel so
    // the conversion / UDL callbacks can arrive during the short
    // re-prime window and short-circuit the whole wait chain.
    final Future<void> bureauStart =
        bureau.start().timeout(const Duration(seconds: 4), onTimeout: () {});
    await bureau.primeClickSources();
    // One quick re-prime covers Play Services that only answers
    // once the radio has fully come up (offline → online case).
    // Each prime round is already time-boxed on the Kotlin side,
    // so the whole retry window stays under ~1.5 s.
    const List<int> rePrimeDelaysMs = <int>[600, 1200];
    for (int i = 0;
        i < rePrimeDelaysMs.length &&
            !bureau.hasWake &&
            !bureau.hasPaidSignal &&
            !bureau.hasCampaignFields;
        i++) {
      // ignore: avoid_print
      print('[LF/DISP] firstLaunch.primeClickSources#$i empty → re-prime '
          'after ${rePrimeDelaysMs[i]}ms');
      await Future<void>.delayed(
        Duration(milliseconds: rePrimeDelaysMs[i]),
      );
      await bureau.primeClickSources();
      // ignore: avoid_print
      print('[LF/DISP] firstLaunch.primeClickSources.retry#$i '
          'hasWake=${bureau.hasWake} hasPaid=${bureau.hasPaidSignal} '
          'campaign=${bureau.hasCampaignFields}');
    }
    await bureauStart;
    // Always wait the full first-launch window even if we already
    // have a paid-click stamp from Play Install Referrer. The
    // install gate can close on a thin OneLink echo (af_status
    // flipped, af_sub* still empty). The campaign wait stays
    // open until media_source / af_sub* actually arrive — that
    // is the body the backend paints green. Posting the thin
    // echo plus Play's `utm_medium=organic` referrer is what
    // made the offline OneLink boot render sub_id_1 = Organic
    // until the next cold start, when AppsFlyer served the
    // cached conversion immediately.
    await Future.wait<void>(<Future<void>>[
      bureau.awaitSignals(
        installSeconds: PrismSettings.firstLaunchAwaitSeconds,
      ),
      bureau.awaitCampaign(
        seconds: PrismSettings.firstLaunchAwaitSeconds,
      ),
    ]);
    final PrismRoute? lateTap = await _consumeTap();
    if (lateTap != null) {
      progress(1);
      return lateTap;
    }
    progress(0.76);
    // settleOnline is a backup GCD poll — skip when the campaign
    // row is already in hand, otherwise its hard-coded delays
    // dominate the warmup budget without changing the body we
    // send.
    if (!bureau.hasCampaignFields) {
      await bureau.settleOnline();
    }
    final Ruling ruling = await _requestRuling();
    progress(1);
    // ignore: avoid_print
    print('[LF/DISP] firstLaunch.ruling '
        'hasTarget=${ruling.hasTarget} note=${ruling.note} '
        'url=${ruling.url} wake=${bureau.wakeUrl}');
    if (ruling.hasTarget) {
      await vault.storeRoute(RouteMemo.webShell);
      await vault.writeTarget(ruling.url!, ruling.expiresAt);
      // ignore: avoid_print
      print('[LF/DISP] firstLaunch → Shell(ruling ${ruling.url})');
      return ShellRoute(ruling.url!);
    }
    // OneLink fallback: attribution shows a real UDL click that
    // carried a landing URL in the deep-link payload, but the
    // ruling endpoint returned no explicit target (silent backend
    // or not-yet-mapped campaign). Honour the OneLink URL directly
    // — that is exactly what the click promised the user.
    final String? wake = bureau.wakeUrl;
    if (wake != null && wake.isNotEmpty) {
      await vault.storeRoute(RouteMemo.webShell);
      await vault.writeTarget(wake, null);
      // ignore: avoid_print
      print('[LF/DISP] firstLaunch → Shell(wake $wake)');
      return ShellRoute(wake);
    }
    // A dropped POST must not be remembered as organic. The next
    // online retry has to be free to read the real referrer.
    if (_transportFailure(ruling)) {
      // ignore: avoid_print
      print('[LF/DISP] firstLaunch → NoLink (transport fail)');
      return const NoLinkRoute(canFallToGame: false);
    }
    await vault.storeRoute(RouteMemo.nativeGame);
    // ignore: avoid_print
    print('[LF/DISP] firstLaunch → Native');
    return const NativeRoute();
  }

  Future<PrismRoute> _resolveReturningShell(
    void Function(double) progress,
  ) async {
    if (!await _adapterUp()) {
      return const NoLinkRoute(canFallToGame: false);
    }

    final String? pending = await vault.takePending();
    if (pending != null && pending.isNotEmpty) {
      progress(1);
      return ShellRoute(pending);
    }

    final String? cached = await vault.cachedTarget();
    if (cached != null && !vault.cachedTargetExpired) {
      progress(1);
      return ShellRoute(cached);
    }

    await Future.wait<void>(<Future<void>>[
      pushGate.ignite().timeout(const Duration(seconds: 4), onTimeout: () {}),
      bureau.start().timeout(const Duration(seconds: 4), onTimeout: () {}),
    ]);
    if (!await _online()) {
      if (cached != null) return ShellRoute(cached);
      return const NoLinkRoute(canFallToGame: false);
    }
    progress(0.62);
    await bureau.awaitSignals(
      installSeconds: PrismSettings.returningAwaitSeconds,
    );
    final PrismRoute? lateTap = await _consumeTap();
    if (lateTap != null) {
      progress(1);
      return lateTap;
    }
    if (!bureau.hasCampaignFields) {
      await bureau.settleOnline();
    }
    final Ruling ruling = await _requestRuling();
    progress(1);
    if (ruling.hasTarget) return ShellRoute(ruling.url!);
    if (cached != null) return ShellRoute(cached);
    return const NoLinkRoute(canFallToGame: false);
  }

  Future<PrismRoute> _resolveReturningNative(
    void Function(double) progress,
  ) async {
    if (!await _adapterUp()) {
      progress(1);
      return const NativeRoute();
    }
    await Future.wait<void>(<Future<void>>[
      pushGate.ignite().timeout(const Duration(seconds: 4), onTimeout: () {}),
      bureau.start().timeout(const Duration(seconds: 4), onTimeout: () {}),
    ]);
    if (!await _online()) {
      progress(1);
      return const NativeRoute();
    }
    progress(0.58);
    await bureau.awaitSignals(
      installSeconds: PrismSettings.returningAwaitSeconds,
    );
    final PrismRoute? lateTap = await _consumeTap();
    if (lateTap != null) {
      progress(1);
      return lateTap;
    }
    if (!bureau.hasCampaignFields) {
      await bureau.settleOnline();
    }
    final Ruling ruling = await _requestRuling();
    progress(1);
    if (ruling.hasTarget) {
      await vault.storeRoute(RouteMemo.webShell);
      await vault.writeTarget(ruling.url!, ruling.expiresAt);
      return ShellRoute(ruling.url!);
    }
    // Same OneLink fallback as first-launch: a fresh UDL click on
    // a previously-native install still deserves to open the
    // deep-linked landing when the ruling backend is silent.
    final String? wake = bureau.wakeUrl;
    if (wake != null && wake.isNotEmpty) {
      await vault.storeRoute(RouteMemo.webShell);
      await vault.writeTarget(wake, null);
      return ShellRoute(wake);
    }
    return const NativeRoute();
  }

  Future<Ruling> _requestRuling({String? token}) async {
    final Map<String, dynamic> body = await bureau.assemble(
      locale: Platform.localeName.replaceAll('-', '_'),
      pushToken: token ?? pushGate.token,
    );
    return endpoint.query(body);
  }

  Future<void> _backgroundRefresh() async {
    try {
      await Future.wait<void>(<Future<void>>[
        pushGate.ignite(),
        bureau.start(),
      ]);
      await bureau.awaitSignals(
        installSeconds: PrismSettings.returningAwaitSeconds,
      );
      if (!bureau.hasCampaignFields) {
        await bureau.awaitCampaign(
          seconds: PrismSettings.firstLaunchAwaitSeconds,
        );
      }
      await bureau.settleOnline();
      if (!bureau.hasCampaignFields) return;
      await _requestRuling();
    } catch (_) {}
  }

  Future<void> _refreshOnTokenRotate(String token) async {
    // FCM often hands the token the moment the radio returns,
    // which on an offline OneLink install is BEFORE AppsFlyer
    // has filled the campaign row. Posting here latches
    // sub_id_1 = Organic. The main pipeline reads pushGate.token
    // itself once the campaign row is ready.
    if (!bureau.hasCampaignFields) {
      // ignore: avoid_print
      print('[LF/DISP] token.rotate skip — campaign fields empty');
      return;
    }
    try {
      await _requestRuling(token: token);
    } catch (_) {}
  }

  Future<void> _onLateWake(Map<String, dynamic> click) async {
    try {
      if (!bureau.hasCampaignFields) {
        await bureau.awaitCampaign(
          seconds: PrismSettings.firstLaunchAwaitSeconds,
        );
      }
      if (!bureau.hasCampaignFields) {
        // ignore: avoid_print
        print('[LF/DISP] lateWake skip — campaign fields empty');
        return;
      }
      await bureau.settleOnline();
      final Ruling ruling = await _requestRuling();
      if (ruling.hasTarget) {
        await vault.storeRoute(RouteMemo.webShell);
        await vault.writeTarget(ruling.url!, ruling.expiresAt);
        onGrayReady?.call(ruling.url!);
        return;
      }
      final String? wake = bureau.wakeUrl;
      if (wake != null && wake.isNotEmpty) {
        await vault.storeRoute(RouteMemo.webShell);
        await vault.writeTarget(wake, null);
        onGrayReady?.call(wake);
      }
    } catch (_) {}
  }

  Future<PrismRoute?> _consumeTap() async {
    final String? url = await ColdIntent.tap(vault);
    if (url == null || url.isEmpty) return null;
    await vault.storeRoute(RouteMemo.webShell);
    return ShellRoute(url, coldTap: true);
  }

  Future<bool> _adapterUp() async {
    try {
      return !await gauge
          .isDefinitelyOffline()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return true;
    }
  }

  bool _transportFailure(Ruling ruling) {
    final String note = ruling.note ?? '';
    return note.startsWith('network:');
  }

  Future<bool> _online() async {
    // Fast path: one probe. If it answers, we are online — no
    // reason to spend another 900 ms + DNS round-trip just to
    // confirm it. The slower retry only runs when the first
    // probe failed outright (handles the DNS-priming race on
    // the boundary of a fresh connectivity event).
    try {
      final Stopwatch sw = Stopwatch()..start();
      final bool ok = await gauge.canReach();
      // ignore: avoid_print
      print('[LF/NET] canReach#0=$ok in ${sw.elapsedMilliseconds}ms');
      if (ok) return true;
    } catch (e) {
      // ignore: avoid_print
      print('[LF/NET] canReach#0.fail $e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      final Stopwatch sw = Stopwatch()..start();
      final bool ok = await gauge.canReach();
      // ignore: avoid_print
      print('[LF/NET] canReach#1=$ok in ${sw.elapsedMilliseconds}ms');
      return ok;
    } catch (e) {
      // ignore: avoid_print
      print('[LF/NET] canReach#1.fail $e');
      return false;
    }
  }
}
