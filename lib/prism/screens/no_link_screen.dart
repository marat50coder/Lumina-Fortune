import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../controls.dart';
import '../net/link_gauge.dart';

// ─────────────────────────────────────────────────────────────
// NO-LINK SCREEN — shown whenever the pipeline concludes "no
// network". Retry rebuilds the caller-supplied route through
// `pushReplacement`. The pipeline is idempotent by design — the
// dispatcher's in-flight cache clears on completion, so Retry
// runs the full boot flow fresh (attribution → probe → ruling).
//
// Per project brief: NO background image. Solid/gradient fill
// + text "NO INTERNET CONNECTION / Check your connection and
// try again". Retry button is a warm gold pill sized
// orientation-aware (pitfalls §18).
// ─────────────────────────────────────────────────────────────

class NoLinkScreen extends StatefulWidget {
  const NoLinkScreen({
    super.key,
    required this.rebuildRoute,
  });

  final WidgetBuilder rebuildRoute;

  @override
  State<NoLinkScreen> createState() => _NoLinkScreenState();
}

class _NoLinkScreenState extends State<NoLinkScreen> {
  bool _spinning = false;
  StreamSubscription<List<ConnectivityResult>>? _linkSub;

  @override
  void initState() {
    super.initState();
    _linkSub = LinkGauge().changes.listen((List<ConnectivityResult> states) {
      final bool live = states.any(
        (ConnectivityResult e) =>
            e != ConnectivityResult.none,
      );
      if (live) unawaited(_autoResume());
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _autoResume() async {
    // A single connectivity event fires the instant the OS notices
    // an adapter transitioned to CONNECTED, but DNS + the routing
    // table often take another second or two to settle. Rushing
    // the retry here surfaces a second NoLink after the retry's
    // own DNS probe fails, which reads as "shown twice" to the
    // user. Wait long enough for the network to actually reach
    // the internet before we hand control back to the dispatcher.
    try {
      final bool up = await LinkGauge()
          .hasAdapter()
          .timeout(const Duration(milliseconds: 1600));
      if (!up) return;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      final bool reachable = await LinkGauge()
          .canReach()
          .timeout(const Duration(seconds: 6), onTimeout: () => false);
      if (reachable && mounted) await _retry();
    } catch (_) {}
  }

  Future<void> _retry() async {
    if (_spinning) return;
    setState(() => _spinning = true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.rebuildRoute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final Size size = mq.size;
    final bool landscape = mq.orientation == Orientation.landscape;

    // Landscape-aware safe padding covers a punch-hole notch on
    // any long-edge orientation (pitfalls §14).
    final EdgeInsets safe = landscape
        ? EdgeInsets.only(
            left: mq.viewPadding.left,
            right: mq.viewPadding.right,
            top: mq.viewPadding.top,
            bottom: mq.viewPadding.bottom,
          )
        : EdgeInsets.only(
            top: mq.viewPadding.top,
            bottom: mq.viewPadding.bottom,
          );

    return Scaffold(
      backgroundColor: const Color(0xFF0E1F0F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            radius: 1.1,
            colors: <Color>[
              Color(0xFF204B26),
              Color(0xFF122616),
              Color(0xFF0A130C),
            ],
            stops: <double>[0.0, 0.55, 1.0],
          ),
        ),
        child: Padding(
          padding: safe,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: landscape ? size.width * 0.10 : 28,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _GlowGlyph(size: landscape ? 68 : 96),
                  SizedBox(height: landscape ? 14 : 26),
                  Text(
                    'NO INTERNET CONNECTION',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Fredoka',
                      fontSize: landscape ? 22 : 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      color: const Color(0xFFFFF6D8),
                      height: 1.15,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Color(0xB3000000),
                          offset: Offset(0, 3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: landscape ? 8 : 14),
                  Text(
                    'Check your connection and try again',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: landscape ? 15 : 17,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFDCE7C7),
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: landscape ? 20 : 34),
                  if (_spinning)
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFF5C542),
                        ),
                      ),
                    )
                  else
                    GlowButton(
                      text: 'Try Again',
                      icon: Icons.refresh_rounded,
                      onPress: _retry,
                      width: landscape
                          ? size.width * 0.30
                          : (size.width * 0.62).clamp(220, 360),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowGlyph extends StatelessWidget {
  const _GlowGlyph({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: <Color>[Color(0xFFF5C542), Color(0xFF1F4A24)],
          stops: <double>[0.0, 1.0],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFF5C542).withValues(alpha: 0.55),
            blurRadius: 26,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.wifi_off_rounded,
        size: 48,
        color: Color(0xFF5A3516),
      ),
    );
  }
}
