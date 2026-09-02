import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/assets.dart';
import '../core/audio.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';
import 'level_select_screen.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const CoverBg(A.bgBellwood),
          const Vignette(dark: 0.28),
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
                      const Expanded(child: TitleBanner('Progress Map')),
                      const SizedBox(width: 46),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: Catalog.zones.length,
                      itemBuilder: (context, i) {
                        final z = Catalog.zones[i];
                        final open = g.zoneOpen(z.id);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            children: [
                              if (i > 0)
                                Container(
                                  width: 6,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: open ? Lf.gold : Colors.white24,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              GestureDetector(
                                onTap: open
                                    ? () {
                                        AudioHub.I.open();
                                        Navigator.push(
                                          context,
                                          FadeRoute(LevelSelectScreen(zone: z)),
                                        );
                                      }
                                    : null,
                                child: WoodPanel(
                                  gold: open,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: open ? Lf.gold : Colors.white24,
                                        child: Text(
                                          '${i + 1}',
                                          style: Lf.title.copyWith(color: Lf.ink, fontSize: 18),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(z.name, style: Lf.title.copyWith(fontSize: 18)),
                                            Text(
                                              open
                                                  ? 'Day ${g.nextPlayableDay(z) + 1} / ${z.days}'
                                                  : 'Locked',
                                              style: Lf.body.copyWith(fontSize: 13, color: Colors.white70),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(open ? Icons.chevron_right : Icons.lock, color: Lf.cream),
                                    ],
                                  ),
                                ),
                              ),
                            ],
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
