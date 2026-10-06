import 'diag.dart';
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
    // Re-evaluate invite gating on every resume. Aggressive
    // process retention (ColorOS / MIUI / EMUI) can keep the
    // WebShell alive for days after a "Skip" tap; without this,
    // the invite screen would never resurface until the process
    // was actually terminated. See invite-snooze flow in
    // PrismSettings.inviteSnoozeSeconds.
    _reevaluateInviteAfterResume();
  }

  Future<void> _reevaluateInviteAfterResume() async {
    if (_openingGray) return;
    if (!widget.vault.shouldShowInvite) return;
    final NavigatorState? nav = _nav.currentState;
    if (nav == null) return;
    // Only interrupt the shell path вЂ” never the native game or
    // the warmup / no-link screens.
    final String? targetUrl = await _peekActiveShellUrl();
    if (targetUrl == null || targetUrl.isEmpty) return;
    if (!mounted) return;
    _openingGray = true;
    plog(() => '[LF/INVITE] resume.reopen target=$targetUrl');
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => InviteScreen(
          vault: widget.vault,
          pushGate: widget.pushGate,
          targetUrl: targetUrl,
        ),
      ),
      (Route<dynamic> _) => false,
    );
    _openingGray = false;
  }

  /// Returns the URL the user should return to AFTER seeing the
  /// invite again вЂ” i.e. the current shell target. `null` when
  /// there is no shell to bounce back to (native game path).
  Future<String?> _peekActiveShellUrl() async {
    final String? cached = await widget.vault.cachedTarget();
    if (cached != null &&
        cached.isNotEmpty &&
        !widget.vault.cachedTargetExpired) {
      return cached;
    }
    return null;
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
