import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// PRISM CONTROLS — buttons for the gray-flow screens
// ─────────────────────────────────────────────────────────────
// Deliberately styled differently from the template's frosted-
// blue relay pill AND from the white-part wooden buttons of the
// native game. Warm gold pill for the primary action, deep-forest
// outlined pill for the secondary — matches the Lumina Fortune
// palette without reusing any asset from the game menu.
//
// Every label uses `height: 1.0` and `CrossAxisAlignment.center`
// to defeat baseline drift (see pitfalls doc §13). Skip buttons
// are ALWAYS a real gradient pill — never a text link with
// reduced opacity (pitfalls §12).
// ─────────────────────────────────────────────────────────────

/// Primary warm-gold pill button. Used for Accept / Retry.
class GlowButton extends StatefulWidget {
  const GlowButton({
    super.key,
    required this.text,
    required this.onPress,
    this.icon,
    this.compact = false,
    this.width,
    this.height,
  });

  final String text;
  final VoidCallback onPress;
  final IconData? icon;
  final bool compact;
  final double? width;
  final double? height;

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double vPad = widget.compact ? 12 : 16;
    final double fSize = widget.compact ? 16 : 19;
    final double? boxH = widget.height;
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.94),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onPress();
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 90),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (BuildContext ctx, Widget? _) {
            final double glow = 8 + _pulse.value * 8;
            return Container(
              width: widget.width,
              height: boxH,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal: 22,
                vertical: boxH == null ? vPad : 0,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    Color(0xFFFFE27A),
                    Color(0xFFF5C542),
                    Color(0xFFC48A14),
                  ],
                  stops: <double>[0.0, 0.55, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: const Color(0xFFFFF6D8).withValues(alpha: 0.85),
                  width: 2,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFC48A14).withValues(alpha: 0.55),
                    offset: const Offset(0, 4),
                    blurRadius: 0,
                  ),
                  BoxShadow(
                    color: const Color(0xFFFFE27A).withValues(alpha: 0.45),
                    blurRadius: glow,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  if (widget.icon != null) ...<Widget>[
                    Icon(widget.icon, size: fSize + 2, color: const Color(0xFF5A3516)),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.text.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Fredoka',
                        color: const Color(0xFF5A3516),
                        fontSize: fSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Secondary deep-forest outlined pill. Used for Skip.
/// A real gradient button — never a text link with reduced
/// opacity (pitfalls §12).
class LeafButton extends StatefulWidget {
  const LeafButton({
    super.key,
    required this.text,
    required this.onPress,
    this.compact = false,
    this.width,
    this.height,
  });

  final String text;
  final VoidCallback onPress;
  final bool compact;
  final double? width;
  final double? height;

  @override
  State<LeafButton> createState() => _LeafButtonState();
}

class _LeafButtonState extends State<LeafButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final double vPad = widget.compact ? 12 : 16;
    final double fSize = widget.compact ? 16 : 19;
    final double? boxH = widget.height;
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.94),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onPress();
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: widget.width,
          height: boxH,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(
            horizontal: 22,
            vertical: boxH == null ? vPad : 0,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[
                Color(0xFF3E8B3A),
                Color(0xFF1F4A24),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFF6BCB4A).withValues(alpha: 0.85),
              width: 2,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0xAA000000),
                offset: Offset(0, 4),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  widget.text.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Fredoka',
                    color: const Color(0xFFFFF6D8),
                    fontSize: fSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
