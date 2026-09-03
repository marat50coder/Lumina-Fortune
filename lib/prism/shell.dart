import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/game_controller.dart';
import 'dispatcher.dart';
import 'net/local_vault.dart';
import 'net/push_gate.dart';
import 'screens/invite_screen.dart';
import 'screens/no_link_screen.dart';
import 'screens/warmup_screen.dart';
import 'screens/web_shell.dart';
import 'settings.dart';

/// Root MaterialApp. Owns the long-lived infrastructure (vault,
/// pushGate, dispatcher, and the white-part GameController) and
/// hands them to the warmup screen.
class LuminaShell extends StatefulWidget {
  const LuminaShell({
    super.key,
    required this.dispatcher,
    required this.vault,
    required this.pushGate,
    this.startOffline = false,
  });

  final PrismDispatcher dispatcher;
  final LocalVault vault;
  final PushGate pushGate;
  final bool startOffline;

  @override
  State<LuminaShell> createState() => _LuminaShellState();
}

class _LuminaShellState extends State<LuminaShell>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();
  bool _openingGray = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.dispatcher.onGrayReady = _openGray;
  }

  @override
  void dispose() {
    if (widget.dispatcher.onGrayReady == _openGray) {
      widget.dispatcher.onGrayReady = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    widget.dispatcher.bureau.recheckDeepLink();
  }

  WarmupScreen _warmup() {
    return WarmupScreen(
      dispatcher: widget.dispatcher,
      vault: widget.vault,
      pushGate: widget.pushGate,
    );
  }

  void _openGray(String url) {
    if (_openingGray || url.isEmpty) return;
    final NavigatorState? nav = _nav.currentState;
    if (nav == null) return;
    _openingGray = true;
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => widget.vault.shouldShowInvite
            ? InviteScreen(
                vault: widget.vault,
                pushGate: widget.pushGate,
                targetUrl: url,
              )
            : WebShell(
                url: url,
                vault: widget.vault,
                pushGate: widget.pushGate,
              ),
      ),
      (Route<dynamic> _) => false,
    );
    _openingGray = false;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameController>(
      create: (_) => GameController(),
      child: MaterialApp(
        title: PrismSettings.labelText,
        navigatorKey: _nav,
        debugShowCheckedModeBanner: false,
        theme: Lf.theme(),
        home: widget.startOffline
            ? NoLinkScreen(rebuildRoute: (_) => _warmup())
            : _warmup(),
      ),
    );
  }
}
