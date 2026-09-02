import 'package:flutter/material.dart';

import '../core/assets.dart';
import '../core/audio.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';
import 'gameplay_screen.dart';
import 'level_select_screen.dart';
import 'menu_screen.dart';
import 'upgrades_screen.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.result, required this.zone});
  final DayResult result;
  final ZoneDef zone;

  bool get _hasNext => result.success && result.day + 1 < zone.days;

  void _openLevels(BuildContext context) {
    AudioHub.I.open();
    Navigator.of(context).pushAndRemoveUntil(
      FadeRoute(LevelSelectScreen(zone: zone)),
      (r) => r.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CoverBg(zone.background),
          const Vignette(dark: 0.36),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                children: [
                  TitleBanner(
                    result.success ? Catalog.dayTitle(zone.id, result.day) : 'Chain Faded',
                    size: 28,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Day ${result.day + 1} of ${zone.days}',
                    style: Lf.body.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  StarRow(filled: result.stars, size: 40),
                  const SizedBox(height: 16),
                  WoodPanel(
                    child: Column(
                      children: [
                        _row('Caught', '${result.caught}'),
                        _row('Missed', '${result.missed}'),
                        _row('Chain', '${result.chain}'),
                        _row('Score', '${result.score}'),
                        _row('Lumina Coins', '+${result.coins}'),
                        if (result.rGained > 0) _row('R Emblems', '+${result.rGained}'),
                        if (result.starHit) _row('Lumina Burst', 'Awakened'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Sprite(result.success ? A.basketGold : A.basketWood, height: 110),
                  const Spacer(),
                  if (_hasNext)
                    GroveButton(
                      label: 'NEXT DAY',
                      width: 240,
                      onTap: () {
                        AudioHub.I.open();
                        Navigator.pushReplacement(
                          context,
                          FadeRoute(GameplayScreen(zone: zone, day: result.day + 1)),
                        );
                      },
                    )
                  else
                    GroveButton(
                      label: result.success ? 'DAYS' : 'TRY AGAIN',
                      width: 240,
                      onTap: () {
                        if (result.success) {
                          _openLevels(context);
                        } else {
                          Navigator.pushReplacement(
                            context,
                            FadeRoute(GameplayScreen(zone: zone, day: result.day)),
                          );
                        }
                      },
                    ),
                  const SizedBox(height: 10),
                  GroveButton(
                    label: 'DAY SELECT',
                    width: 240,
                    color: Lf.goldDark,
                    dark: const Color(0xFF7A560C),
                    onTap: () => _openLevels(context),
                  ),
                  const SizedBox(height: 10),
                  GroveButton(
                    label: 'UPGRADES',
                    width: 240,
                    color: Lf.sky,
                    dark: const Color(0xFF1E5A88),
                    onTap: () => Navigator.push(context, FadeRoute(const UpgradesScreen())),
                  ),
                  const SizedBox(height: 10),
                  GroveButton(
                    label: 'MAIN MENU',
                    width: 240,
                    color: const Color(0xFF6B5A4A),
                    dark: const Color(0xFF3A2E24),
                    onTap: () {
                      AudioHub.I.close();
                      Navigator.of(context).pushAndRemoveUntil(
                        FadeRoute(const MenuScreen()),
                        (r) => false,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(k, style: Lf.body.copyWith(fontSize: 16))),
          Text(v, style: Lf.title.copyWith(fontSize: 18, color: Lf.goldHot)),
        ],
      ),
    );
  }
}
