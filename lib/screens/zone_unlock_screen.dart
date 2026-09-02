import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/audio.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';
import 'level_select_screen.dart';

class ZoneUnlockScreen extends StatelessWidget {
  const ZoneUnlockScreen({super.key, required this.zone});
  final ZoneDef zone;

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CoverBg(zone.background),
          const Vignette(dark: 0.34),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                    ],
                  ),
                  const Spacer(),
                  const TitleBanner('New Zone Unlocked', size: 28),
                  const SizedBox(height: 16),
                  WoodPanel(
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Sprite(zone.background, height: 180, width: double.infinity, fit: BoxFit.cover),
                        ),
                        const SizedBox(height: 12),
                        Text(zone.name, style: Lf.title.copyWith(fontSize: 24, color: Lf.goldHot)),
                        const SizedBox(height: 6),
                        Text(zone.blurb, textAlign: TextAlign.center, style: Lf.body.copyWith(fontSize: 14)),
                        if (zone.coinUnlock > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Open for ${zone.coinUnlock} coins${zone.rUnlock > 0 ? ' + ${zone.rUnlock} R' : ''}',
                            style: Lf.body.copyWith(color: Lf.goldHot),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  GroveButton(
                    label: g.zoneOpen(zone.id) ? 'CONTINUE' : 'UNLOCK',
                    width: 240,
                    onTap: () {
                      if (!g.zoneOpen(zone.id)) {
                        if (!g.unlockZone(zone)) return;
                      }
                      AudioHub.I.open();
                      Navigator.pushReplacement(
                        context,
                        FadeRoute(LevelSelectScreen(zone: zone)),
                      );
                    },
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
