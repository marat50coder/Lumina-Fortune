import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/audio.dart';
import '../core/theme.dart';
import '../state/game_controller.dart';

class Sprite extends StatelessWidget {
  const Sprite(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );
  }
}

class CoverBg extends StatelessWidget {
  const CoverBg(this.path, {super.key});
  final String path;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(child: Sprite(path, fit: BoxFit.cover));
  }
}

class Vignette extends StatelessWidget {
  const Vignette({super.key, this.dark = 0.22});
  final double dark;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: dark),
                Colors.transparent,
                Colors.black.withValues(alpha: dark + 0.18),
              ],
              stops: const [0, 0.42, 1],
            ),
          ),
        ),
      ),
    );
  }
}

class WoodPanel extends StatelessWidget {
  const WoodPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.gold = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B5A2B), Color(0xFF5A3516)],
        ),
        border: Border.all(color: gold ? Lf.gold : const Color(0xFF3A2412), width: 2.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class GroveButton extends StatelessWidget {
  const GroveButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color = Lf.meadow,
    this.dark = Lf.forest,
    this.width,
    this.height = 52,
    this.fontSize = 20,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color dark;
  final double? width;
  final double height;
  final double fontSize;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled
            ? () {
                AudioHub.I.click();
                AudioHub.I.haptic();
                onTap();
              }
            : null,
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color, dark],
            ),
            border: Border.all(color: Lf.goldHot.withValues(alpha: 0.85), width: 2),
            boxShadow: [
              BoxShadow(
                color: dark.withValues(alpha: 0.45),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Lf.title.copyWith(fontSize: fontSize, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class RoundIconBtn extends StatelessWidget {
  const RoundIconBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 46,
    this.color = Lf.gold,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AudioHub.I.click();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, Colors.black, 0.28)!],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.6),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.48),
      ),
    );
  }
}

class HudBar extends StatelessWidget {
  const HudBar({super.key, this.trailing});
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    return Row(
      children: [
        _Chip(icon: Icons.monetization_on, label: '${g.coins}', tint: Lf.gold),
        const SizedBox(width: 8),
        _Chip(icon: Icons.auto_awesome, label: '${g.rTokens}', tint: const Color(0xFFFFB347)),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.tint});
  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC2A1A0C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 6),
          Text(label, style: Lf.body.copyWith(fontSize: 15, color: Lf.cream)),
        ],
      ),
    );
  }
}

class TitleBanner extends StatelessWidget {
  const TitleBanner(this.text, {super.key, this.size = 26});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Lf.title.copyWith(
        fontSize: size,
        color: Lf.goldHot,
        shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
      ),
    );
  }
}

class LoadingDots extends StatefulWidget {
  const LoadingDots({super.key, this.style});
  final TextStyle? style;

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots> {
  int n = 0;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  Future<void> _tick() async {
    while (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!mounted) return;
      setState(() => n = (n + 1) % 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dots = n == 0 ? '' : List.filled(n, '.').join();
    return Text(
      'Loading$dots',
      style: widget.style ??
          Lf.title.copyWith(
            fontSize: 28,
            color: Colors.white,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 2))],
          ),
    );
  }
}

class LuminaProgressBar extends StatelessWidget {
  const LuminaProgressBar({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final inner = (w - 10) * value.clamp(0.0, 1.0);
        return Container(
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: const Color(0xCC1A140C),
            border: Border.all(color: Lf.gold, width: 2),
            boxShadow: [BoxShadow(color: Lf.gold.withValues(alpha: 0.35), blurRadius: 10)],
          ),
          padding: const EdgeInsets.all(3),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: max(0, inner),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFE27A), Color(0xFFF5C542), Color(0xFF6BCB4A)],
                ),
                boxShadow: const [BoxShadow(color: Color(0xAAFFC938), blurRadius: 8)],
              ),
            ),
          ),
        );
      },
    );
  }
}

class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.filled, this.size = 28});
  final int filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            i < filled ? Icons.star_rounded : Icons.star_border_rounded,
            color: i < filled ? Lf.goldHot : Colors.white24,
            size: size,
          ),
        );
      }),
    );
  }
}
