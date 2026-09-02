import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/assets.dart';
import '../core/audio.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const CoverBg(A.bgAncient),
          const Vignette(dark: 0.36),
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
                      const Expanded(child: TitleBanner('Achievements')),
                      const SizedBox(width: 46),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${g.achievements.length} / ${Catalog.achievements.length}',
                    style: Lf.body.copyWith(color: Lf.goldHot),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: Catalog.achievements.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final a = Catalog.achievements[i];
                        final done = g.achievements.contains(a.id);
                        return WoodPanel(
                          gold: done,
                          child: Row(
                            children: [
                              Icon(
                                done ? Icons.emoji_events : Icons.emoji_events_outlined,
                                color: done ? Lf.goldHot : Colors.white38,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.title, style: Lf.title.copyWith(fontSize: 17)),
                                    Text(a.detail, style: Lf.body.copyWith(fontSize: 13, color: Colors.white70)),
                                  ],
                                ),
                              ),
                              if (done) const Icon(Icons.check_circle, color: Lf.leaf),
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
