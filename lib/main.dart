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
  FirebaseMessaging.onBackgroundMessage(prismBgPush);

  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
  ));

  final LinkGauge gauge = LinkGauge();
  bool startOffline = false;
  try {
    startOffline = await gauge
        .isDefinitelyOffline()
        .timeout(const Duration(milliseconds: 900));
  } catch (_) {
    startOffline = false;
  }

  final LocalVault vault = LocalVault();
  try {
    await vault.warm().timeout(const Duration(seconds: 2));
  } catch (_) {}

  final PushGate pushGate = PushGate(vault);
  final TrackerBureau bureau = TrackerBureau();
  final PrismDispatcher dispatcher = PrismDispatcher(
    vault: vault,
    gauge: gauge,
    bureau: bureau,
    endpoint: RulingEndpoint(vault),
    pushGate: pushGate,
  );

  if (startOffline) {
    runApp(LuminaShell(
      dispatcher: dispatcher,
      vault: vault,
      pushGate: pushGate,
      startOffline: true,
    ));
    return;
  }

  FirebaseMessaging.onBackgroundMessage(prismBgPush);
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp().timeout(const Duration(seconds: 6));
    }
  } catch (_) {}

  try {
    await UaForger.prime().timeout(const Duration(seconds: 3));
  } catch (_) {}
  unawaited(bureau.start());
  unawaited(pushGate.ignite());

  runApp(LuminaShell(
    dispatcher: dispatcher,
    vault: vault,
    pushGate: pushGate,
  ));
}
