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
    });
  }

  Future<PrismRoute> _resolve(void Function(double) progress) async {
    if (!PrismSettings.gateReady) {
      progress(1);
      return const NativeRoute();
    }

    pushGate.onTokenRotate = _refreshOnTokenRotate;

    // Park the current tap inside ignite first. Reading the vault
    // before that would replay a leftover URL from another push.
    try {
      await pushGate.ignite().timeout(const Duration(seconds: 6));
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
    if (!await _adapterUp()) {
      return const NoLinkRoute(canFallToGame: false);
    }
    progress(0.32);
    // Prime AppsFlyer BEFORE gating on network. The Google Play
    // Install-Referrer broadcast still lands offline; the SDK
    // captures + queues it, and when the user retries with the
    // network back up, the stored referrer delivers real
    // attribution instead of a stale organic fallback.
    unawaited(bureau.start());
    try {
      await pushGate.ignite().timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (!await _online()) {
      return const NoLinkRoute(canFallToGame: false);
    }
    progress(0.48);
    // Retry-safe: `start()` short-circuits when init already
    // succeeded, otherwise it re-runs `initSdk` on the same SDK
    // instance with the network now available.
    try {
      await bureau.start().timeout(const Duration(seconds: 8));
    } catch (_) {}
    await bureau.awaitSignals(
      installSeconds: bureau.hasWake
          ? PrismSettings.returningAwaitSeconds
          : PrismSettings.firstLaunchAwaitSeconds,
    );
    final PrismRoute? lateTap = await _consumeTap();
    if (lateTap != null) {
      progress(1);
      return lateTap;
    }
    progress(0.76);
    final Ruling ruling = await _requestRuling();
    progress(1);
    if (ruling.hasTarget) {
      await vault.storeRoute(RouteMemo.webShell);
      return ShellRoute(ruling.url!);
    }
    await vault.storeRoute(RouteMemo.nativeGame);
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
      pushGate.ignite().timeout(const Duration(seconds: 8), onTimeout: () {}),
      bureau.start().timeout(const Duration(seconds: 8), onTimeout: () {}),
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
      pushGate.ignite().timeout(const Duration(seconds: 8), onTimeout: () {}),
      bureau.start().timeout(const Duration(seconds: 8), onTimeout: () {}),
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
    final Ruling ruling = await _requestRuling();
    progress(1);
    if (!ruling.hasTarget) return const NativeRoute();
    await vault.storeRoute(RouteMemo.webShell);
    return ShellRoute(ruling.url!);
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
      await _requestRuling();
    } catch (_) {}
  }

  Future<void> _refreshOnTokenRotate(String token) async {
    try {
      await _requestRuling(token: token);
    } catch (_) {}
  }

  Future<void> _onLateWake(Map<String, dynamic> _) async {
    try {
      final Ruling ruling = await _requestRuling();
      if (!ruling.hasTarget) return;
      await vault.storeRoute(RouteMemo.webShell);
      onGrayReady?.call(ruling.url!);
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

  Future<bool> _online() async {
    try {
      return await gauge.canReach().timeout(const Duration(seconds: 8));
    } catch (_) {
      return true;
    }
  }
}
