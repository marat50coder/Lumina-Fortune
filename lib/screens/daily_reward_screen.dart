import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/assets.dart';
import '../core/audio.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';

class DailyRewardScreen extends StatelessWidget {
  const DailyRewardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    final idx = g.dailyIndex;
    final ready = g.dailyReady;
    final gift = Catalog.dailyTable[idx];
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const CoverBg(A.bgGlade),
          const Vignette(dark: 0.34),
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
                      const Expanded(child: TitleBanner('Daily Reward')),
                      const SizedBox(width: 46),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (ready) _readyBody(context, g, gift) else _claimedBody(context, g, idx),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readyBody(BuildContext context, GameController g, ({int coins, int r, String label}) gift) {
    return Expanded(
      child: Column(
        children: [
          const SizedBox(height: 6),
          Text('Day ${(g.dailyIndex % 7) + 1} of 7',
              style: Lf.title.copyWith(fontSize: 22, color: Lf.goldHot)),
          const Spacer(),
          _GiftHero(sprite: A.basketGold, glow: true),
          const SizedBox(height: 12),
          WoodPanel(
            child: Column(
              children: [
                Text(gift.label, style: Lf.body.copyWith(fontSize: 18)),
                const SizedBox(height: 6),
                Text(
                  '+${gift.coins} coins${gift.r > 0 ? '   +${gift.r} R' : ''}',
                  style: Lf.title.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 12),
                _WeekStrip(claims: g.dailyClaims, activeIndex: g.dailyIndex, ready: true),
              ],
            ),
          ),
          const Spacer(),
          GroveButton(
            label: 'CLAIM',
            width: 260,
            onTap: () {
              if (g.claimDaily()) {
                AudioHub.I.open();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _claimedBody(BuildContext context, GameController g, int idx) {
    // Preview the next gift and show a countdown to midnight
    final nextIdx = (idx) % Catalog.dailyTable.length; // dailyIndex already advanced after claim
    final preview = Catalog.dailyTable[nextIdx];
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final left = tomorrow.difference(now);
    String hh(int n) => n.toString().padLeft(2, '0');

    return Expanded(
      child: Column(
        children: [
          const SizedBox(height: 6),
          WoodPanel(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Lf.leaf, size: 22),
                    const SizedBox(width: 8),
                    Text('Today claimed', style: Lf.title.copyWith(fontSize: 18)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _GiftHero(sprite: A.basketWood, glow: false, dim: 0.45),
          const SizedBox(height: 14),
          WoodPanel(
            gold: false,
            child: Column(
              children: [
                Text('Next reward in', style: Lf.body.copyWith(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  '${hh(left.inHours)}:${hh(left.inMinutes.remainder(60))}:${hh(left.inSeconds.remainder(60))}',
                  style: Lf.title.copyWith(fontSize: 30, color: Lf.goldHot),
                ),
                const SizedBox(height: 10),
                _PreviewRow(gift: preview),
                const SizedBox(height: 12),
                _WeekStrip(claims: g.dailyClaims, activeIndex: nextIdx, ready: false),
              ],
            ),
          ),
          const Spacer(),
          Text(
            'Come back tomorrow — the grove grows richer every day.',
            textAlign: TextAlign.center,
            style: Lf.body.copyWith(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _GiftHero extends StatelessWidget {
  const _GiftHero({required this.sprite, required this.glow, this.dim = 0});
  final String sprite;
  final bool glow;
  final double dim;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (glow)
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Lf.goldHot.withValues(alpha: 0.55),
                    Lf.goldHot.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          Opacity(
            opacity: dim > 0 ? 1 - dim : 1,
            child: Sprite(sprite, height: 180),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.gift});
  final ({int coins, int r, String label}) gift;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PreviewChip(icon: Icons.monetization_on_rounded, value: '+${gift.coins}', color: Lf.gold),
        if (gift.r > 0) ...[
          const SizedBox(width: 8),
          _PreviewChip(icon: Icons.auto_awesome_rounded, value: '+${gift.r} R', color: const Color(0xFFFFB347)),
        ],
        const SizedBox(width: 10),
        Text(gift.label, style: Lf.body.copyWith(fontSize: 13, color: Colors.white70)),
      ],
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.icon, required this.value, required this.color});
  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xCC1A140C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(value, style: Lf.body.copyWith(fontSize: 13, color: Colors.white)),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.claims, required this.activeIndex, required this.ready});
  final int claims;
  final int activeIndex;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(7, (i) {
          final claimedDay = (claims % 7) > i;
          final isActive = i == activeIndex && ready;
          final isNext = i == activeIndex && !ready;
          return _DayCell(day: i + 1, claimed: claimedDay, active: isActive, next: isNext);
        }),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.claimed, required this.active, required this.next});
  final int day;
  final bool claimed;
  final bool active;
  final bool next;

  @override
  Widget build(BuildContext context) {
    Color border = Colors.white24;
    Color fill = Colors.black26;
    Widget child = Text('$day', style: Lf.body.copyWith(fontSize: 13));
    if (claimed) {
      border = Lf.leaf;
      fill = Lf.leaf.withValues(alpha: 0.25);
      child = const Icon(Icons.check_rounded, color: Lf.leaf, size: 18);
    } else if (active) {
      border = Lf.goldHot;
      fill = Lf.goldHot.withValues(alpha: 0.28);
      child = Text('$day', style: Lf.title.copyWith(fontSize: 15, color: Lf.goldHot));
    } else if (next) {
      border = Lf.gold;
      fill = Lf.gold.withValues(alpha: 0.15);
      child = Text('$day', style: Lf.title.copyWith(fontSize: 15, color: Lf.goldHot));
    }
    return Container(
      width: 36,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: fill,
        border: Border.all(color: border, width: 1.6),
      ),
      child: child,
    );
  }
}
