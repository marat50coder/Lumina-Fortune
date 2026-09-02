import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/audio.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';
import 'level_select_screen.dart';
import 'zone_unlock_screen.dart';

class ZoneSelectScreen extends StatelessWidget {
  const ZoneSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CoverBg(Catalog.zones.first.background),
          const Vignette(dark: 0.32),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
                      const Expanded(child: TitleBanner('Forest Zones')),
                      const SizedBox(width: 46),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const HudBar(),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: Catalog.zones.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final z = Catalog.zones[i];
                        final open = g.zoneOpen(z.id);
                        final cleared = g.zoneCleared(z);
                        return GestureDetector(
                          onTap: () {
                            AudioHub.I.click();
                            if (open) {
                              Navigator.push(context, FadeRoute(LevelSelectScreen(zone: z)));
                            } else if (g.canUnlock(z)) {
                              Navigator.push(context, FadeRoute(ZoneUnlockScreen(zone: z)));
                            }
                          },
                          child: WoodPanel(
                            gold: open,
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Sprite(z.background, width: 72, height: 88, fit: BoxFit.cover),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(z.name, style: Lf.title.copyWith(fontSize: 18, color: Lf.goldHot)),
                                      const SizedBox(height: 4),
                                      Text(
                                        open ? z.blurb : 'Locked grove',
                                        style: Lf.body.copyWith(fontSize: 13, color: Colors.white70),
                                      ),
                                      const SizedBox(height: 6),
                                      if (open)
                                        StarRow(
                                          filled: List.generate(z.days, (d) => g.dayStars['${z.id}_$d'] ?? 0)
                                              .fold<int>(0, (a, b) => a + (b > 0 ? 1 : 0))
                                              .clamp(0, 3),
                                          size: 18,
                                        )
                                      else
                                        Text(
                                          z.unlockAfter == null
                                              ? 'Open'
                                              : 'Clear ${Catalog.zone(z.unlockAfter!).name}  •  ${z.coinUnlock} coins${z.rUnlock > 0 ? ' + ${z.rUnlock} R' : ''}',
                                          style: Lf.body.copyWith(fontSize: 12, color: Lf.cream),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  open
                                      ? (cleared ? Icons.check_circle : Icons.play_arrow_rounded)
                                      : Icons.lock,
                                  color: open ? Lf.leaf : Colors.white38,
                                  size: 28,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
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
