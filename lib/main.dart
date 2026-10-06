import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prism/dispatcher.dart';
import 'prism/net/link_gauge.dart';
import 'prism/net/local_vault.dart';
import 'prism/net/push_gate.dart';
import 'prism/net/ruling_endpoint.dart';
import 'prism/net/tracker_bureau.dart';
import 'prism/net/ua_forger.dart';
import 'prism/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: avoid_print
  print('[LF/MAIN] boot');
  // Background push handler must be registered before the first
  // frame — it is instant, no await needed.
  FirebaseMessaging.onBackgroundMessage(prismBgPush);

  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
  ));

  final LinkGauge gauge = LinkGauge();
  final LocalVault vault = LocalVault();
  final PushGate pushGate = PushGate(vault);
  final TrackerBureau bureau = TrackerBureau();
  final PrismDispatcher dispatcher = PrismDispatcher(
    vault: vault,
    gauge: gauge,
    bureau: bureau,
    endpoint: RulingEndpoint(vault),
    pushGate: pushGate,
  );

  // SharedPreferences warms in <100 ms on a healthy device.
  // A longer window just idled the system splash before the
  // warmup screen had a chance to render anything.
  try {
    await vault.warm().timeout(const Duration(milliseconds: 500));
  } catch (_) {}

  // One quick adapter check — no retry. If it is ambiguous we
  // continue optimistically; the dispatcher runs a real DNS
  // probe once the warmup screen is up anyway, so a second
  // check here was pure latency on the system splash.
  bool startOffline = false;
  try {
    startOffline = await gauge
        .isDefinitelyOffline()
        .timeout(const Duration(milliseconds: 350));
  } catch (_) {}
  // ignore: avoid_print
  print('[LF/MAIN] startOffline=$startOffline');

  if (startOffline) {
    runApp(LuminaShell(
      dispatcher: dispatcher,
      vault: vault,
      pushGate: pushGate,
      startOffline: true,
    ));
    return;
  }

  // Firebase.initializeApp + UaForger.prime used to block here
  // for up to 9 s before the first frame. Both are idempotent
  // and have safe fallbacks:
  //   • Firebase.initializeApp is called again inside
  //     pushGate.ignite() during dispatcher.resolve.
  //   • UaForger has a code-unit seed fallback, and the WebView
  //     reads the cached value lazily on first use.
  // Running them unawaited lets runApp fire immediately so the
  // warmup screen replaces the system splash within ~100 ms.
  unawaited(_warmFirebase());
  unawaited(UaForger.prime());

  runApp(LuminaShell(
    dispatcher: dispatcher,
    vault: vault,
    pushGate: pushGate,
  ));
}

Future<void> _warmFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
}
