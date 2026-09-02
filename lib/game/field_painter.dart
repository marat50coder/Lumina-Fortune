import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/assets.dart';
import '../core/theme.dart';
import 'field_types.dart';

class FieldPainter extends CustomPainter {
  FieldPainter({
    required this.objects,
    required this.sparks,
    required this.floaters,
    required this.images,
    required this.alpha,
    required this.basketX,
    required this.basketY,
    required this.basketHalf,
    required this.basketLean,
    required this.catchFlash,
    required this.wind,
    required this.frame,
  });

  final List<FieldObj> objects;
  final List<FieldSpark> sparks;
  final List<FieldFloater> floaters;
  final Map<String, ui.Image> images;
  final double alpha;
  final double basketX;
  final double basketY;
  final double basketHalf;
  final double basketLean;
  final double catchFlash;
  final double wind;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    final sparkPaint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()..style = PaintingStyle.fill;

    if (wind.abs() > 0.08) {
      final streak = Paint()
        ..color = Colors.white.withValues(alpha: 0.10 * wind.abs().clamp(0, 1))
        ..strokeWidth = 1.4;
      for (var i = 0; i < 7; i++) {
        final y = size.height * (0.22 + i * 0.08);
        final x0 = wind > 0 ? 20.0 : size.width - 20;
        canvas.drawLine(Offset(x0, y), Offset(x0 + wind.sign * 46, y - 6), streak);
      }
    }

    for (final o in objects) {
      if (o.collected) continue;
      _drawObject(canvas, size, o, glowPaint);
    }

    for (final s in sparks) {
      final p = Offset(s.pos.dx * size.width, s.pos.dy * size.height);
      sparkPaint.color = s.color.withValues(alpha: s.life.clamp(0, 1));
      if (s.leaf) {
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(s.life * 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: s.size * 1.6, height: s.size),
            const Radius.circular(3),
          ),
          sparkPaint,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(p, s.size * 0.55, sparkPaint);
      }
    }

    for (final f in floaters) {
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: Lf.title.copyWith(
            fontSize: f.big ? 20 : 16,
            color: f.color.withValues(alpha: f.life.clamp(0, 1)),
            shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120);
      tp.paint(
        canvas,
        Offset(f.pos.dx * size.width - tp.width / 2, f.pos.dy * size.height - tp.height / 2),
      );
    }

    _drawBasket(canvas, size);
    _drawSlider(canvas, size);
  }

  Offset _drawPos(FieldObj o) => Offset.lerp(o.prevPos, o.pos, alpha) ?? o.pos;

  void _drawObject(Canvas canvas, Size size, FieldObj o, Paint glowPaint) {
    final pos = _drawPos(o);
    final cx = pos.dx * size.width;
    var cy = pos.dy * size.height;
    if (o.hanging && !o.scenery) {
      cy += sin(o.wobble) * (o.kind == ObjKind.bell ? 3.0 : 2.2);
    } else if (!o.hanging && !o.scenery) {
      cy += sin(o.wobble * 1.6) * 1.6;
    }

    if (o.kind == ObjKind.bell) {
      _drawBellAura(canvas, size, o, Offset(cx, cy), glowPaint);
    } else if (o.kind == ObjKind.star) {
      glowPaint.shader = ui.Gradient.radial(
        Offset(cx, cy),
        size.width * o.radius * 2.4,
        [
          Lf.goldHot.withValues(alpha: 0.30 + o.glow * 0.4),
          Lf.goldHot.withValues(alpha: 0),
        ],
      );
      canvas.drawCircle(Offset(cx, cy), size.width * o.radius * 1.7, glowPaint);
      glowPaint.shader = null;
    } else if (o.glow > 0) {
      glowPaint.shader = ui.Gradient.radial(
        Offset(cx, cy),
        size.width * o.radius * 1.8,
        [
          Lf.goldHot.withValues(alpha: 0.35 * o.glow),
          Lf.goldHot.withValues(alpha: 0),
        ],
      );
      canvas.drawCircle(Offset(cx, cy), size.width * o.radius * 1.3, glowPaint);
      glowPaint.shader = null;
    }

    final img = images[o.sprite];
    if (img == null) return;

    final side = size.width * o.radius * 2.05;
    final falling = !o.hanging && !o.scenery;
    final stretchY = falling ? (1 + o.vel.dy * 0.10).clamp(0.94, 1.12) : 1.0;
    final stretchX = falling ? (1 - o.vel.dy * 0.05).clamp(0.90, 1.06) : 1.0;
    final tilt = o.kind == ObjKind.bell
        ? o.ringTilt + sin(o.wobble * 2.2) * (0.14 + o.ringPulse * 0.35)
        : (o.hanging && !o.fixed && !o.scenery ? sin(o.wobble * 0.7) * 0.05 : o.spin);
    final bellSquash = o.kind == ObjKind.bell ? 1 + o.ringPulse * 0.12 : 1.0;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(tilt);
    canvas.scale(stretchX * bellSquash, stretchY / bellSquash);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromCenter(center: Offset.zero, width: side, height: side);
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  void _drawBellAura(Canvas canvas, Size size, FieldObj o, Offset c, Paint glowPaint) {
    final r = size.width * o.radius;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(c.dx, c.dy + r * 1.15), width: r * 1.6, height: r * 0.35),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
    glowPaint.shader = ui.Gradient.radial(
      c,
      r * 2.4,
      [
        const Color(0xFFFFC938).withValues(alpha: 0.18 + o.glow * 0.35),
        const Color(0xFFFFC938).withValues(alpha: 0),
      ],
    );
    canvas.drawCircle(c, r * 1.7, glowPaint);
    glowPaint.shader = null;
    if (o.ringPulse > 0.04) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = Lf.goldHot.withValues(alpha: o.ringPulse * 0.85);
      canvas.drawCircle(c, r * (1.3 + (1 - o.ringPulse) * 1.8), ring);
      canvas.drawCircle(c, r * (1.6 + (1 - o.ringPulse) * 2.6), ring..color = Lf.goldHot.withValues(alpha: o.ringPulse * 0.4));
    }
  }

  void _drawBasket(Canvas canvas, Size size) {
    final img = images[A.basketWood];
    if (img == null) return;
    final width = size.width * basketHalf * 2.15;
    final cx = basketX * size.width;
    final cy = basketY * size.height - width * 0.18;
    if (catchFlash > 0) {
      final g = Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          width * 0.9,
          [
            Lf.goldHot.withValues(alpha: 0.55 * catchFlash),
            Lf.goldHot.withValues(alpha: 0),
          ],
        );
      canvas.drawCircle(Offset(cx, cy), width * 0.7, g);
    }
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(basketLean);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: width, height: width * 0.82),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  void _drawSlider(Canvas canvas, Size size) {
    const trackH = 52.0;
    const knob = 48.0;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(16, size.height - trackH - 12, size.width - 32, trackH),
      const Radius.circular(26),
    );
    canvas.drawRRect(
      track,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height - trackH - 12),
          Offset(0, size.height - 12),
          const [Color(0xE01A140C), Color(0xE0000000)],
        ),
    );
    canvas.drawRRect(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = Lf.goldHot.withValues(alpha: 0.8),
    );

    final inner = Rect.fromLTWH(26, size.height - 12 - trackH / 2 - 3, size.width - 52, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, const Radius.circular(3)),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );

    final knobX = 16 + (size.width - 32) * basketX;
    final knobY = size.height - 12 - trackH / 2;
    canvas.drawCircle(
      Offset(knobX, knobY),
      knob / 2 + 4,
      Paint()..color = const Color(0x55FFC938),
    );
    canvas.drawCircle(
      Offset(knobX, knobY),
      knob / 2,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(knobX - 6, knobY - 6),
          knob,
          const [Color(0xFFFFF3B0), Color(0xFFF5B733)],
        ),
    );
    canvas.drawCircle(
      Offset(knobX, knobY),
      knob / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant FieldPainter old) => old.frame != frame;
}
