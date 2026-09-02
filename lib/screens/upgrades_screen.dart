import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/assets.dart';
import '../core/audio.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';

class UpgradesScreen extends StatelessWidget {
  const UpgradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const CoverBg(A.bgGlade),
          const Vignette(dark: 0.34),
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
                      const Expanded(child: TitleBanner('Grove Upgrades')),
                      const SizedBox(width: 46),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const HudBar(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: Catalog.upgrades.map((u) {
                        final lv = g.levelOf(u.id);
                        final maxed = lv >= u.maxLevel;
                        final cost = Catalog.upgradeCost(u, lv);
                        final can = !maxed && g.coins >= cost && g.rTokens >= u.rCost;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: WoodPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(u.title, style: Lf.title.copyWith(fontSize: 18, color: Lf.goldHot)),
                                    ),
                                    Text('Lv $lv / ${u.maxLevel}', style: Lf.body.copyWith(fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(u.detail, style: Lf.body.copyWith(fontSize: 13, color: Colors.white70)),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: lv / u.maxLevel,
                                    minHeight: 8,
                                    color: Lf.leaf,
                                    backgroundColor: Colors.black26,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: GroveButton(
                                    label: maxed
                                        ? 'MAX'
                                        : 'BUY  $cost${u.rCost > 0 ? ' + ${u.rCost} R' : ''}',
                                    width: 180,
                                    height: 42,
                                    fontSize: 15,
                                    enabled: can,
                                    onTap: () {
                                      if (g.buyUpgrade(u.id)) {
                                        AudioHub.I.open();
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
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
