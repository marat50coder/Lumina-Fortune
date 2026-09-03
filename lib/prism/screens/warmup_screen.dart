import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/assets.dart';
import '../../screens/menu_screen.dart' as white_menu;
import '../../state/game_controller.dart';
import '../dispatcher.dart';
import '../net/local_vault.dart';
import '../net/push_gate.dart';
import '../net/ua_forger.dart';
import '../routing.dart';
import 'invite_screen.dart';
import 'no_link_screen.dart';
import 'web_shell.dart';

// ─────────────────────────────────────────────────────────────
// WARMUP SCREEN — the ONLY startup surface
// ─────────────────────────────────────────────────────────────
// One responsibility: show the loading art + progress bar while
// [PrismDispatcher.resolve] returns a [PrismRoute], then
// destructure the sealed type and push exactly one route. This
// file contains zero routing logic beyond `switch (route)`.
// ─────────────────────────────────────────────────────────────

class WarmupScreen extends StatefulWidget {
  const WarmupScreen({
    super.key,
    required this.dispatcher,
    required this.vault,
    required this.pushGate,
  });

  final PrismDispatcher dispatcher;
  final LocalVault vault;
  final PushGate pushGate;

  @override
  State<WarmupScreen> createState() => _WarmupScreenState();
}

class _WarmupScreenState extends State<WarmupScreen>
    with TickerProviderStateMixin {
  static const Duration _dotsPeriod = Duration(milliseconds: 1_200);

  double _fillTarget = 0.06;
  double _fillShown = 0.02;
  bool _landed = false;
  late final AnimationController _dots;
  late final Ticker _creepTicker;

  @override
  void initState() {
    super.initState();
    _dots = AnimationController(vsync: this, duration: _dotsPeriod)
      ..repeat();
    _creepTicker = createTicker(_onCreepTick)..start();
    _drive();
  }

  @override
  void dispose() {
    _creepTicker.dispose();
    _dots.dispose();
    super.dispose();
  }

  Future<void> _drive() async {
    unawaited(UaForger.prime());
    PrismRoute outcome = const NativeRoute();
    try {
      outcome = await widget.dispatcher.resolve(onProgress: _bumpProgress);
    } catch (_) {
      outcome = const NativeRoute();
    }
    if (!mounted || _landed) return;
    _landed = true;
    _fillTarget = 1;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    Widget next;
    try {
      next = switch (outcome) {
        NativeRoute() => await _buildNativeRoute(),
        ShellRoute(url: final String url) => _buildShellRoute(url: url),
        NoLinkRoute() => _buildNoLinkRoute(),
      };
    } catch (_) {
      next = const white_menu.MenuScreen();
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => next),
    );
  }

  Future<Widget> _buildNativeRoute() async {
    // Fire-and-forget — awaiting this on ColorOS 15 can stall
    // the platform channel and freeze Loading forever.
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    if (!mounted) return const white_menu.MenuScreen();
    try {
      final GameController g = context.read<GameController>();
      await g.load().timeout(const Duration(seconds: 3));
      if (!mounted) return const white_menu.MenuScreen();
      for (final String path in A.bootImages.take(8)) {
        if (!mounted) break;
        try {
          await precacheImage(AssetImage(path), context)
              .timeout(const Duration(milliseconds: 400));
        } catch (_) {}
      }
    } catch (_) {}
    return const white_menu.MenuScreen();
  }

  Widget _buildShellRoute({required String url}) {
    if (widget.vault.shouldShowInvite) {
      return InviteScreen(
        vault: widget.vault,
        pushGate: widget.pushGate,
        targetUrl: url,
      );
    }
    return WebShell(
      url: url,
      vault: widget.vault,
      pushGate: widget.pushGate,
    );
  }

  Widget _buildNoLinkRoute() {
    return NoLinkScreen(
      rebuildRoute: (_) => WarmupScreen(
        dispatcher: widget.dispatcher,
        vault: widget.vault,
        pushGate: widget.pushGate,
      ),
    );
  }

  void _bumpProgress(double v) {
    if (!mounted) return;
    setState(() => _fillTarget = v.clamp(0.0, 1.0));
  }

  void _onCreepTick(Duration _) {
    if (!mounted) return;
    if ((_fillShown - _fillTarget).abs() < 0.001) return;
    setState(() {
      final double delta = (_fillTarget - _fillShown) * 0.09;
      _fillShown =
          (_fillShown + delta).clamp(0.0, _fillTarget);
    });
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final bool landscape = mq.orientation == Orientation.landscape;
    final String bg = landscape
        ? 'assets/lf_prism_pack/warmup_landscape.webp'
        : 'assets/lf_prism_pack/warmup_portrait.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF0E1F0F),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(bg, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.transparent, Color(0x99000000)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                landscape ? 72 : 34,
                0,
                landscape ? 72 : 34,
                landscape ? 22 : 44,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  AnimatedBuilder(
                    animation: _dots,
                    builder: (BuildContext ctx, Widget? _) {
                      final int n = (_dots.value * 4).floor() % 4;
                      return Text(
                        'Loading${'.' * n}',
                        style: TextStyle(
                          fontFamily: 'Fredoka',
                          fontSize: landscape ? 22 : 26,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFFFF6D8),
                          letterSpacing: 1.4,
                          height: 1.0,
                          shadows: const <Shadow>[
                            Shadow(
                              color: Color(0xB3000000),
                              offset: Offset(0, 2),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _GlowRail(value: _fillShown),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowRail extends StatelessWidget {
  const _GlowRail({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        return Container(
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0x66000000),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFFFF6D8).withValues(alpha: 0.75),
              width: 2,
            ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              width: c.maxWidth * value.clamp(0.0, 1.0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    Color(0xFFFFE27A),
                    Color(0xFFF5C542),
                    Color(0xFFC48A14),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFF5C542).withValues(alpha: 0.55),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
