import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/assets.dart';
import '../core/audio.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';
import 'webview_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const CoverBg(A.bgMeadow),
          const Vignette(dark: 0.35),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      RoundIconBtn(
                        icon: Icons.arrow_back,
                        onTap: () {
                          AudioHub.I.close();
                          Navigator.pop(context);
                        },
                      ),
                      const Expanded(child: TitleBanner('Settings')),
                      const SizedBox(width: 46),
                    ],
                  ),
                  const SizedBox(height: 18),
                  WoodPanel(
                    child: Column(
                      children: [
                        _Toggle('Music', g.music, (v) => g.setFlag(musicOn: v)),
                        _Toggle('Sound', g.sfx, (v) => g.setFlag(sfxOn: v)),
                        _Toggle('Vibration', g.vibrate, (v) => g.setFlag(vibeOn: v)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  GroveButton(
                    label: 'PRIVACY POLICY',
                    width: double.infinity,
                    color: Lf.sky,
                    dark: const Color(0xFF1E5A88),
                    onTap: () {
                      Navigator.push(
                        context,
                        FadeRoute(const WebPageScreen(title: 'Privacy Policy', url: Urls.privacy)),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  GroveButton(
                    label: 'SUPPORT',
                    width: double.infinity,
                    color: Lf.wood,
                    dark: Lf.woodDark,
                    onTap: () {
                      Navigator.push(
                        context,
                        FadeRoute(const WebPageScreen(title: 'Support', url: Urls.support)),
                      );
                    },
                  ),
                  const Spacer(),
                  Text(
                    'Lumina Fortune',
                    style: Lf.body.copyWith(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.value, this.onChanged);
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Lf.body.copyWith(fontSize: 18))),
          Switch.adaptive(
            value: value,
            activeThumbColor: Lf.gold,
            onChanged: (v) {
              AudioHub.I.click();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
