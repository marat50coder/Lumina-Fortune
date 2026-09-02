import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/assets.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';
import 'menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  double _shown = 0.02;
  double _cap = 0.86;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    hideChrome();
    unlockOrientation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final g = context.read<GameController>();
    _creep();
    await g.load();
    if (!mounted) return;
    setState(() => _cap = 0.58);
    for (final a in A.bootImages) {
      await precacheImage(AssetImage(a), context);
      if (!mounted) return;
    }
    setState(() => _cap = 0.86);
    for (final a in A.gameplayImages.take(16)) {
      await precacheImage(AssetImage(a), context);
      if (!mounted) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    _ready = true;
    setState(() {
      _cap = 1;
      _shown = 1;
    });
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    await lockPortrait();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(FadeRoute(const MenuScreen()));
  }

  Future<void> _creep() async {
    while (mounted && !_ready) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!mounted || _ready) return;
      setState(() {
        if (_shown < _cap) {
          _shown = (_shown + 0.011).clamp(0, _cap);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Sprite(portrait ? A.loadingV : A.loadingH, fit: BoxFit.cover),
          const Vignette(dark: 0.08),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                portrait ? 28 : 72,
                16,
                portrait ? 28 : 72,
                portrait ? 36 : 22,
              ),
              child: Column(
                children: [
                  const Spacer(),
                  const LoadingDots(),
                  const SizedBox(height: 14),
                  LuminaProgressBar(value: _shown),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
