import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/assets.dart';
import '../core/audio.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';
import 'achievements_screen.dart';
import 'collection_screen.dart';
import 'daily_reward_screen.dart';
import 'level_select_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';
import 'upgrades_screen.dart';
import 'zone_select_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  @override
  void initState() {
    super.initState();
    hideChrome();
    lockPortrait();
  }

  void _play() {
    final g = context.read<GameController>();
    AudioHub.I.open();
    ZoneDef zone = Catalog.zones.first;
    for (final z in Catalog.zones) {
      if (g.zoneOpen(z.id) && !g.zoneCleared(z)) {
        zone = z;
        break;
      }
      if (g.zoneOpen(z.id)) zone = z;
    }
    Navigator.push(context, FadeRoute(LevelSelectScreen(zone: zone)));
  }

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const CoverBg(A.bgMeadow),
          const Vignette(dark: 0.22),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                children: [
                  HudBar(),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.center,
                    child: Sprite(A.gameName, height: 168),
                  ),
                  Expanded(
                    flex: 5,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Sprite(
                        A.keeper,
                        height: MediaQuery.sizeOf(context).height * 0.30,
                      ),
                    ),
                  ),
                  GroveButton(label: 'PLAY', width: 260, height: 62, fontSize: 28, onTap: _play),
                  const SizedBox(height: 16),
                  _MenuGrid(
                    items: [
                      _MenuItem(
                        'Zones',
                        Icons.map_rounded,
                        () => Navigator.push(context, FadeRoute(const ZoneSelectScreen())),
                      ),
                      _MenuItem(
                        'Upgrades',
                        Icons.auto_fix_high_rounded,
                        () => Navigator.push(context, FadeRoute(const UpgradesScreen())),
                      ),
                      _MenuItem(
                        'Album',
                        Icons.grid_view_rounded,
                        () => Navigator.push(context, FadeRoute(const CollectionScreen())),
                      ),
                      _MenuItem(
                        'Map',
                        Icons.route_rounded,
                        () => Navigator.push(context, FadeRoute(const MapScreen())),
                      ),
                      _MenuItem(
                        g.dailyReady ? 'Daily' : 'Claimed',
                        Icons.card_giftcard_rounded,
                        () => Navigator.push(context, FadeRoute(const DailyRewardScreen())),
                      ),
                      _MenuItem(
                        'Awards',
                        Icons.emoji_events_rounded,
                        () => Navigator.push(context, FadeRoute(const AchievementsScreen())),
                      ),
                      _MenuItem(
                        'Settings',
                        Icons.settings_rounded,
                        () => Navigator.push(context, FadeRoute(const SettingsScreen())),
                      ),
                    ],
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

class _MenuItem {
  const _MenuItem(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid({required this.items});
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    // Uniform-size secondary buttons, laid out in rows that fit the width.
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        const cols = 4;
        final btnW = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: items
              .map((it) => SizedBox(
                    width: btnW,
                    child: _MenuButton(item: it),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.item});
  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AudioHub.I.click();
        item.onTap();
      },
      child: Container(
        height: 74,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF8B5A2B), Color(0xFF5A3516)],
          ),
          border: Border.all(color: Lf.goldHot.withValues(alpha: 0.85), width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 26, color: Lf.goldHot),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Lf.body.copyWith(fontSize: 12, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
