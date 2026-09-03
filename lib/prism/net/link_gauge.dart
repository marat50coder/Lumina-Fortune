import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../settings.dart';

// ─────────────────────────────────────────────────────────────
// LINK GAUGE — connectivity + DNS reachability
// ─────────────────────────────────────────────────────────────
// `connectivity_plus` alone is unreliable — captive portals,
// half-brought-up VPN interfaces, mobile-data cells without a
// route all report "connected". We layer a real DNS lookup on
// top so the pipeline never commits to online routing without a
// working DNS path.
//
// ⚠️ VPN counts as connectivity. See pitfalls doc §3.
// ─────────────────────────────────────────────────────────────

// Rotate this pair per project. Two cheap-DNS hosts unrelated
// to the partner AND the ruling endpoint.
const List<String> _probeHosts = <String>[
  'apple.com',
  'wikipedia.org',
];

// Adapters that count as "up". Whitelisting VPN + Bluetooth +
// Ethernet mirrors pitfalls doc §3.A.
const Set<ConnectivityResult> _liveAdapters = <ConnectivityResult>{
  ConnectivityResult.wifi,
  ConnectivityResult.mobile,
  ConnectivityResult.ethernet,
  ConnectivityResult.vpn,
  ConnectivityResult.bluetooth,
  ConnectivityResult.other,
};

class LinkGauge {
  LinkGauge({Connectivity? connectivity})
      : _plugin = connectivity ?? Connectivity();

  final Connectivity _plugin;
  int _rotor = 0;

  /// True if at least one adapter reports as live. Empty / error
  /// fail open — a plugin stall must not flash NoWifi. Does NOT
  /// run a DNS probe — use [canReach] for that.
  Future<bool> hasAdapter() async {
    try {
      final List<ConnectivityResult> states =
          await _plugin.checkConnectivity();
      if (states.isEmpty) return true;
      return states.any(_liveAdapters.contains);
    } catch (_) {
      return true;
    }
  }

  /// True only when the plugin reports a sustained `none`. A
  /// single cold-start `[none]` on ColorOS is often a lie — we
  /// re-check once before committing to the offline shell.
  Future<bool> isDefinitelyOffline() async {
    try {
      if (!await _allNone()) return false;
      await Future<void>.delayed(const Duration(milliseconds: 320));
      return await _allNone();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _allNone() async {
    final List<ConnectivityResult> states = await _plugin.checkConnectivity();
    if (states.isEmpty) return false;
    return states.every((ConnectivityResult e) => e == ConnectivityResult.none);
  }

  /// True if we can resolve at least one probe host within the
  /// timeout. Rotates hosts so a briefly-unresolvable host does
  /// not force a retry cycle.
  Future<bool> canReach() async {
    if (await isDefinitelyOffline()) return false;
    final Duration timeout =
        Duration(seconds: PrismSettings.dnsProbeSeconds);
    for (int i = 0; i < _probeHosts.length; i++) {
      final String host =
          _probeHosts[(_rotor + i) % _probeHosts.length];
      try {
        final List<InternetAddress> answer =
            await InternetAddress.lookup(host).timeout(timeout);
        if (answer.any((InternetAddress a) => a.rawAddress.isNotEmpty)) {
          _rotor = (_rotor + 1) % _probeHosts.length;
          return true;
        }
      } catch (_) {
        // Fall through to the next host before declaring offline.
      }
    }
    return false;
  }

  Stream<List<ConnectivityResult>> get changes =>
      _plugin.onConnectivityChanged;
}
