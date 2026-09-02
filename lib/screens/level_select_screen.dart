import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/audio.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';
import 'gameplay_screen.dart';

class LevelSelectScreen extends StatelessWidget {
  const LevelSelectScreen({super.key, required this.zone});
  final ZoneDef zone;

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CoverBg(zone.background),
          const Vignette(dark: 0.38),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
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
                      Expanded(child: TitleBanner(zone.name)),
                      const SizedBox(width: 46),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pick a day. Later days add wind, more wardens, and a higher quota.',
                    textAlign: TextAlign.center,
                    style: Lf.body.copyWith(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  const HudBar(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.92,
                      ),
                      itemCount: zone.days,
                      itemBuilder: (context, day) {
                        final open = g.dayUnlocked(zone, day);
                        final stars = g.starsOn(zone, day);
                        final current = open && stars == 0 && g.nextPlayableDay(zone) == day;
                        return _DayCard(
                          zone: zone,
                          day: day,
                          open: open,
                          stars: stars,
                          current: current,
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

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.zone,
    required this.day,
    required this.open,
    required this.stars,
    required this.current,
  });

  final ZoneDef zone;
  final int day;
  final bool open;
  final int stars;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final quota = zone.minCollect + day;
    return GestureDetector(
      onTap: open
          ? () {
              AudioHub.I.open();
              Navigator.push(context, FadeRoute(GameplayScreen(zone: zone, day: day)));
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: open
                ? (current
                    ? const [Color(0xFF7A5618), Color(0xFF3A2A10)]
                    : const [Color(0xCC8B5A2B), Color(0xCC3A2412)])
                : const [Color(0xAA2A2218), Color(0xAA16120E)],
          ),
          border: Border.all(
            color: current ? Lf.goldHot : (open ? Lf.gold.withValues(alpha: 0.7) : Colors.white24),
            width: current ? 2.4 : 1.4,
          ),
          boxShadow: [
            if (current) const BoxShadow(color: Color(0x66FFC938), blurRadius: 14),
            const BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('DAY ${day + 1}', style: Lf.title.copyWith(fontSize: 13, color: Lf.goldHot)),
                const Spacer(),
                if (!open) const Icon(Icons.lock_rounded, size: 18, color: Colors.white38),
                if (open && current)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Lf.goldHot,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('NOW', style: Lf.title.copyWith(fontSize: 10, color: Lf.ink)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              Catalog.dayTitle(zone.id, day),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Lf.title.copyWith(fontSize: 18, color: open ? Lf.cream : Colors.white54),
            ),
            const Spacer(),
            Text(
              open ? 'Catch $quota  •  ${2 + (day > 1 ? 1 : 0)} drops' : 'Clear the previous day',
              style: Lf.body.copyWith(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            StarRow(filled: stars, size: 22),
          ],
        ),
      ),
    );
  }
}
