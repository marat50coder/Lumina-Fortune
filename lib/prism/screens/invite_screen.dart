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
    final MediaQueryData mq = MediaQuery.of(context);
    final Size size = mq.size;
    final bool landscape = mq.orientation == Orientation.landscape;
    final String bg = landscape
        ? 'assets/lf_prism_pack/invite_landscape.webp'
        : 'assets/lf_prism_pack/invite_portrait.webp';

    // Same pill for both actions. Landscape sits them on one
    // row at the Skip-button height (Ocean Fortune layout).
    final double btnW = landscape
        ? size.width * 0.28
        : (size.width * 0.70).clamp(220.0, 360.0);
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

    return Scaffold(
      backgroundColor: const Color(0xFF0F1F0F),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            bg,
            fit: BoxFit.cover,
            width: size.width,
            height: size.height,
          ),
          Positioned(
            left: size.width * 0.08,
            right: size.width * 0.08,
            bottom: size.height * (landscape ? 0.07 : 0.09),
            child: landscape
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      accept,
                      const SizedBox(width: 16),
                      skip,
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      accept,
                      const SizedBox(height: 16),
                      skip,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
