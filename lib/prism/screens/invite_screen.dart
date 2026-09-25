import 'package:flutter/material.dart';

import '../controls.dart';
import '../net/local_vault.dart';
import '../net/push_gate.dart';
import '../settings.dart';
import 'web_shell.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({
    super.key,
    required this.vault,
    required this.pushGate,
    required this.targetUrl,
  });

  final LocalVault vault;
  final PushGate pushGate;
  final String targetUrl;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  bool _busy = false;
  bool _preloadedBoth = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preloadedBoth) return;
    _preloadedBoth = true;
    // Preload BOTH orientation backgrounds so the swap on
    // rotation is instant (otherwise the OS shows a blank frame
    // while the other WebP decodes).
    precacheImage(
      const AssetImage('assets/lf_prism_pack/invite_portrait.webp'),
      context,
    );
    precacheImage(
      const AssetImage('assets/lf_prism_pack/invite_landscape.webp'),
      context,
    );
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bool granted = await widget.pushGate.requestSystemPermission();
    if (!granted) {
      await widget.vault.writeInviteSnoozeUntil(_snoozeTarget());
    }
    if (mounted) _forward();
  }

  Future<void> _skip() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.vault.writeInviteSnoozeUntil(_snoozeTarget());
    if (mounted) _forward();
  }

  int _snoozeTarget() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 +
      PrismSettings.inviteSnoozeSeconds;

  void _forward() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WebShell(
          url: widget.targetUrl,
          vault: widget.vault,
          pushGate: widget.pushGate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // OrientationBuilder + LayoutBuilder gives us a fresh box on
    // rotation without an intermediate stretched frame. Both
    // backgrounds are precached, and the layout swaps via
    // AnimatedSwitcher so the buttons never mid-fly between
    // absolute positions.
    return Scaffold(
      backgroundColor: const Color(0xFF0F1F0F),
      body: OrientationBuilder(
        builder: (BuildContext ctx, Orientation orientation) {
          final bool landscape = orientation == Orientation.landscape;
          return LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints c) {
              final double w = c.maxWidth;
              final double h = c.maxHeight;
              final String bg = landscape
                  ? 'assets/lf_prism_pack/invite_landscape.webp'
                  : 'assets/lf_prism_pack/invite_portrait.webp';

              final double btnW = landscape
                  ? w * 0.28
                  : (w * 0.70).clamp(220.0, 360.0);
              final double btnH = landscape ? 48.0 : 56.0;

              final Widget accept = GlowButton(
                text: 'Accept',
                icon: Icons.local_fire_department_rounded,
                compact: landscape,
                width: btnW,
                height: btnH,
                onPress: _accept,
              );
              final Widget skip = LeafButton(
                text: 'Skip',
                compact: landscape,
                width: btnW,
                height: btnH,
                onPress: _skip,
              );

              return Stack(
                key: ValueKey<bool>(landscape),
                fit: StackFit.expand,
                children: <Widget>[
                  Image.asset(
                    bg,
                    key: ValueKey<String>(bg),
                    fit: BoxFit.cover,
                    width: w,
                    height: h,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                  Positioned(
                    left: w * 0.08,
                    right: w * 0.08,
                    bottom: h * (landscape ? 0.07 : 0.09),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: landscape
                          ? Row(
                              key: const ValueKey<String>('land-row'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                accept,
                                const SizedBox(width: 16),
                                skip,
                              ],
                            )
                          : Column(
                              key: const ValueKey<String>('port-col'),
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                accept,
                                const SizedBox(height: 16),
                                skip,
                              ],
                            ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
