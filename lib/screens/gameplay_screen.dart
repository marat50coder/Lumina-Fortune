import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../core/assets.dart';
import '../core/audio.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../game/field_painter.dart';
import '../game/field_types.dart';
import '../game/sprite_store.dart';
import '../models/models.dart';
import '../state/game_controller.dart';
import '../widgets/ui.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

class GameplayScreen extends StatefulWidget {
  const GameplayScreen({super.key, required this.zone, required this.day});
  final ZoneDef zone;
  final int day;

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen> with SingleTickerProviderStateMixin {
  static const _step = 1 / 60;

  final rng = Random();
  final objects = <FieldObj>[];
  final floaters = <FieldFloater>[];
  final sparks = <FieldSpark>[];
  final store = SpriteStore();
  final fieldTick = ValueNotifier<int>(0);
  final hudTick = ValueNotifier<int>(0);

  late final Ticker _ticker;
  late final GameController game;
  Duration _last = Duration.zero;
  double _acc = 0;
  double _alpha = 1;
  bool _ready = false;
  bool started = false;
  bool paused = false;
  bool ended = false;
  bool _closing = false;
  bool burst = false;
  bool starHit = false;
  int score = 0;
  int chain = 0;
  int caught = 0;
  int missed = 0;
  int coinsGot = 0;
  int rGot = 0;
  int bellsRung = 0;
  int launchesLeft = 4;
  double still = 0;
  double burstLeft = 0;
  double burstFlash = 0;
  double wind = 0;
  double windT = 0;
  double basketX = 0.5;
  double basketLean = 0;
  double catchFlash = 0;
  final double basketHalf = 0.156;
  final double basketY = 0.81;
  int chainWindow = 0;
  double chainDecay = 0;
  final collected = <String>[];
  Offset? _pointerDown;
  bool _didDrag = false;
  int _hudKey = 0;

  ZoneDef get zone => widget.zone;
  int get quota => zone.minCollect + widget.day;
  int get missCap => widget.day >= 2 ? 2 : 3;

  @override
  void initState() {
    super.initState();
    hideChrome();
    lockPortrait();
    game = context.read<GameController>();
    launchesLeft = 2 + (widget.day > 1 ? 1 : 0) + (game.chainLv >= 3 ? 1 : 0);
    _buildField();
    _loadSprites();
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _loadSprites() async {
    final paths = <String>{
      zone.background,
      A.basketWood,
      ...objects.map((o) => o.sprite),
    };
    await store.load(paths);
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    fieldTick.dispose();
    hudTick.dispose();
    super.dispose();
  }

  void _bumpHud() {
    final key = chain ^
        (caught << 4) ^
        (missed << 8) ^
        (launchesLeft << 12) ^
        (burst ? 1 : 0) ^
        (wind.abs() > 0.15 ? 2 : 0);
    if (key != _hudKey) {
      _hudKey = key;
      hudTick.value++;
    }
  }

  // ---------------- Field setup ----------------

  void _buildField() {
    objects.clear();
    final z = zone;

    void scenery(String sprite, Offset p, double r) {
      objects.add(FieldObj(
        kind: ObjKind.scenery,
        sprite: sprite,
        collectId: '',
        pos: p,
        radius: r,
        value: 0,
        scenery: true,
        fixed: true,
      ));
    }

    scenery(A.treeGreen, const Offset(0.08, 0.17), 0.10);
    scenery(A.treeFruit, const Offset(0.92, 0.21), 0.09);
    scenery(A.stump1, const Offset(0.14, 0.78), 0.048);
    scenery(A.stone1, const Offset(0.86, 0.78), 0.048);
    if (z.id != 'meadow') scenery(A.bushRed, const Offset(0.88, 0.58), 0.05);
    if (z.id == 'bellwood' || z.id == 'ancient') scenery(A.sunTotem, const Offset(0.12, 0.34), 0.05);
    if (z.id == 'grove') scenery(A.plant1, const Offset(0.10, 0.56), 0.038);
    if (z.id == 'glade') scenery(A.plant3, const Offset(0.90, 0.36), 0.042);

    final fruitsPool = <String>[
      A.fruitApple,
      A.fruitOrange,
      A.fruitLemon,
      A.fruitPear,
      A.fruitPeach,
      A.fruitPlum,
      A.fruitCherry,
      A.fruitPomegranate,
    ];
    final berryPool = <String>[
      A.berryStrawberry,
      A.berryRaspberry,
      A.berryBlueberry,
      A.berryBlackberry,
    ];

    final rows = 3 + widget.day ~/ 2;
    final base = 0.26;
    for (var r = 0; r < rows; r++) {
      final y = base + r * 0.085;
      final count = 3 + (r.isOdd ? 1 : 0);
      final offset = r.isOdd ? 0.045 : 0.0;
      for (var c = 0; c < count; c++) {
        final t = (c + 0.5) / count;
        final x = 0.24 + 0.52 * t + offset;
        final berry = z.id == 'grove' ? rng.nextDouble() < 0.55 : rng.nextDouble() < 0.28;
        final sprite = berry ? berryPool[rng.nextInt(berryPool.length)] : fruitsPool[rng.nextInt(fruitsPool.length)];
        _place(
          FieldObj(
            kind: berry ? ObjKind.berry : ObjKind.fruit,
            sprite: sprite,
            collectId: _idFor(sprite),
            pos: Offset(x.clamp(0.22, 0.78), y),
            radius: berry ? 0.038 : 0.046,
            value: berry ? 10 : 14,
          ),
        );
      }
    }

    // Floating wardens in the drop lane. They patrol and bounce fruit UP.
    final bellCount = (1 + widget.day ~/ 2 + (z.id == 'bellwood' || z.id == 'ancient' ? 1 : 0)).clamp(1, 3);
    final lanes = [
      const Offset(0.50, 0.58),
      const Offset(0.30, 0.64),
      const Offset(0.70, 0.62),
    ];
    for (var i = 0; i < bellCount; i++) {
      objects.add(FieldObj(
        kind: ObjKind.bell,
        sprite: i == 0 ? A.bellGold : (i == 1 ? A.bellSun : A.bellBronze),
        collectId: i == 0 ? 'bell_gold' : 'bell_sun',
        pos: lanes[i],
        radius: 0.048,
        value: 8,
        hanging: true,
        fixed: true,
      ));
    }

    if (rng.nextDouble() < 0.7 + game.starLv * 0.03) {
      _place(
        FieldObj(
          kind: ObjKind.star,
          sprite: A.sunStar,
          collectId: 'sun_star',
          pos: const Offset(0.50, 0.20),
          radius: 0.054,
          value: 48,
          hanging: true,
          fixed: true,
        ),
      );
    }

    final coins = 2 + widget.day ~/ 2 + (z.id == 'glade' ? 2 : 0);
    for (var i = 0; i < coins; i++) {
      _place(
        FieldObj(
          kind: ObjKind.coin,
          sprite: A.coins[rng.nextInt(A.coins.length)],
          collectId: 'coin_sun',
          pos: Offset(0.28 + rng.nextDouble() * 0.44, 0.34 + rng.nextDouble() * 0.16),
          radius: 0.032,
          value: 20,
        ),
      );
    }

    if (rng.nextDouble() < game.rareChance) {
      _place(
        FieldObj(
          kind: ObjKind.emblem,
          sprite: A.rEmblem,
          collectId: 'r_emblem',
          pos: Offset(0.34 + rng.nextDouble() * 0.32, 0.33),
          radius: 0.046,
          value: 60,
        ),
      );
    }
    if (rng.nextDouble() < game.rareChance * 0.8) {
      _place(
        FieldObj(
          kind: ObjKind.golden,
          sprite: A.goldenFruit,
          collectId: 'golden_fruit',
          pos: Offset(0.30 + rng.nextDouble() * 0.40, 0.32),
          radius: 0.044,
          value: 42,
        ),
      );
    }
    if (z.id == 'ancient' && rng.nextDouble() < 0.4) {
      _place(
        FieldObj(
          kind: ObjKind.seed,
          sprite: A.seed,
          collectId: 'seed',
          pos: const Offset(0.5, 0.34),
          radius: 0.044,
          value: 34,
        ),
      );
    }

    _separate();
  }

  bool _overlaps(Offset p, double r, {FieldObj? ignore}) {
    for (final o in objects) {
      if (o == ignore || o.scenery) continue;
      if ((o.pos - p).distance < o.radius + r + 0.018) return true;
    }
    return false;
  }

  void _place(FieldObj o, {bool solid = false}) {
    if (!_overlaps(o.pos, o.radius)) {
      objects.add(o);
      return;
    }
    for (var i = 0; i < 28; i++) {
      final nx = (o.pos.dx + (rng.nextDouble() - 0.5) * 0.16).clamp(0.20, 0.80);
      final ny = (o.pos.dy + (rng.nextDouble() - 0.5) * 0.06).clamp(0.18, 0.70);
      final cand = Offset(nx, ny);
      if (!_overlaps(cand, o.radius)) {
        o.pos = cand;
        o.prevPos = cand;
        o.tether = cand;
        objects.add(o);
        return;
      }
    }
    if (solid) {
      objects.add(o);
    }
  }

  void _separate() {
    for (var iter = 0; iter < 10; iter++) {
      for (var i = 0; i < objects.length; i++) {
        final a = objects[i];
        if (a.scenery) continue;
        for (var j = i + 1; j < objects.length; j++) {
          final b = objects[j];
          if (b.scenery) continue;
          final d = a.pos - b.pos;
          final minD = a.radius + b.radius + 0.018;
          final dist = d.distance;
          if (dist >= minD || dist < 1e-5) continue;
          final n = d / dist;
          final push = (minD - dist) * 0.55;
          if (!a.fixed) {
            a.pos += n * push;
            a.pos = Offset(a.pos.dx.clamp(0.18, 0.82), a.pos.dy.clamp(0.16, 0.72));
            a.prevPos = a.pos;
            a.tether = a.pos;
          }
          if (!b.fixed) {
            b.pos -= n * push;
            b.pos = Offset(b.pos.dx.clamp(0.18, 0.82), b.pos.dy.clamp(0.16, 0.72));
            b.prevPos = b.pos;
            b.tether = b.pos;
          }
        }
      }
    }
  }

  String _idFor(String sprite) {
    const map = {
      A.fruitApple: 'apple',
      A.fruitOrange: 'orange',
      A.fruitLemon: 'lemon',
      A.fruitPear: 'pear',
      A.fruitPeach: 'peach',
      A.fruitPlum: 'plum',
      A.fruitCherry: 'cherry',
      A.fruitPomegranate: 'pomegranate',
      A.berryStrawberry: 'strawberry',
      A.berryRaspberry: 'raspberry',
      A.berryBlueberry: 'blueberry',
      A.berryBlackberry: 'blackberry',
    };
    return map[sprite] ?? 'apple';
  }

  // ---------------- Frame update ----------------

  void _onTick(Duration elapsed) {
    if (_last == Duration.zero) {
      _last = elapsed;
      return;
    }
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt > 0.05) dt = 0.05;
    if (paused || ended) return;

    _acc += dt;
    var steps = 0;
    while (_acc >= _step && steps < 3) {
      _simulate(_step);
      _acc -= _step;
      steps++;
    }
    _alpha = (_acc / _step).clamp(0.0, 1.0);
    fieldTick.value++;
    _bumpHud();

    if (ended && !_closing) {
      _finish();
    }
  }

  void _simulate(double dt) {
    var moving = false;
    basketLean *= (1 - dt * 7);
    if (catchFlash > 0) catchFlash = max(0, catchFlash - dt * 3.2);

    windT += dt;
    final gustEvery = 3.4 - widget.day * 0.18;
    if (windT > gustEvery && started) {
      windT = 0;
      wind = (rng.nextBool() ? 1.0 : -1.0) * (0.42 + widget.day * 0.10);
      floaters.add(FieldFloater(wind > 0 ? 'Wind →' : '← Wind', const Offset(0.5, 0.20), 1.0, Lf.sky, big: true));
      _bumpHud();
    }
    wind *= (1 - dt * 0.28);

    for (final o in objects) {
      o.prevPos = o.pos;
      o.wobble += dt * (o.kind == ObjKind.star ? 1.4 : (o.kind == ObjKind.bell ? 1.15 : 1.7));
      o.life += dt;
      if (o.glow > 0) o.glow = max(0, o.glow - dt * 1.4);
      if (o.ringPulse > 0) o.ringPulse = max(0, o.ringPulse - dt * 1.8);
      if (o.kind == ObjKind.bell) {
        o.ringTilt += (0 - o.ringTilt) * min(1, dt * 1.8);
        final amp = 0.11 + widget.day * 0.025;
        o.pos = Offset(
          (o.tether.dx + sin(o.wobble) * amp).clamp(0.16, 0.84),
          o.tether.dy + sin(o.wobble * 1.8) * 0.014,
        );
      }
      if (o.scenery || o.collected) continue;
      if (o.hanging) continue;

      o.vel = Offset(
        o.vel.dx * (1 - dt * 0.32) + wind * dt * 0.62,
        o.vel.dy + 1.28 * dt,
      );
      if (o.vel.dy > 0.92) o.vel = Offset(o.vel.dx, 0.92);
      if (o.vel.dy < -0.62) o.vel = Offset(o.vel.dx, -0.62);
      o.spinVel *= (1 - dt * 0.55);
      o.spinVel = o.spinVel.clamp(-5.5, 5.5);
      o.pos += o.vel * dt;
      o.spin += o.spinVel * dt;

      const wall = 0.08;
      if (o.pos.dx < wall) {
        o.pos = Offset(wall, o.pos.dy);
        o.vel = Offset(max(0.16, o.vel.dx.abs() * 0.4), o.vel.dy);
        o.spinVel *= -0.35;
      }
      if (o.pos.dx > 1 - wall) {
        o.pos = Offset(1 - wall, o.pos.dy);
        o.vel = Offset(-max(0.16, o.vel.dx.abs() * 0.4), o.vel.dy);
        o.spinVel *= -0.35;
      }

      if (o.vel.distance > 0.05) {
        moving = true;
        o.stuck = 0;
      } else {
        o.stuck += dt;
      }

      if (o.stuck > 0.6) {
        o.vel = Offset((0.5 - o.pos.dx).sign * 0.28, 0.34);
        o.pos = Offset(o.pos.dx.clamp(0.20, 0.80), o.pos.dy);
        o.stuck = 0;
      }

      final atBasket = o.pos.dy > basketY - 0.04 && o.pos.dy < basketY + 0.07;
      if (atBasket && o.kind != ObjKind.bell && o.kind != ObjKind.star && !o.countedMiss && !o.collected) {
        final dx = (o.pos.dx - basketX).abs();
        if (dx < basketHalf * 0.76) {
          _catch(o);
        } else if (dx < basketHalf * 1.06 && o.vel.dy > 0.04) {
          o.vel = Offset((o.pos.dx - basketX).sign * 0.24, -0.32);
          o.spinVel += (o.pos.dx - basketX).sign * 3;
          floaters.add(FieldFloater('Rim!', Offset(o.pos.dx, basketY - 0.04), 0.7, Lf.gold));
        }
      }
      if (o.pos.dy > basketY + 0.085 && !o.collected && !o.countedMiss) {
        _miss(o);
      }
    }

    for (var i = 0; i < objects.length; i++) {
      final a = objects[i];
      if (a.scenery || a.collected) continue;
      for (var j = i + 1; j < objects.length; j++) {
        final b = objects[j];
        if (b.scenery || b.collected) continue;
        final d = a.pos - b.pos;
        final dist = d.distance;
        final minD = a.radius + b.radius;
        if (dist < 0.0006 || dist > minD) continue;
        final aFall = !a.hanging && !a.fixed;
        final bFall = !b.hanging && !b.fixed;
        if (!(aFall || bFall)) continue;
        final n = d / max(dist, 1e-4);

        if (a.kind == ObjKind.bell) {
          _bellHit(a, b.vel);
          _bounceOffBell(b, a);
          continue;
        }
        if (b.kind == ObjKind.bell) {
          _bellHit(b, a.vel);
          _bounceOffBell(a, b);
          continue;
        }
        if (a.kind == ObjKind.star) {
          _starHit(a);
          _softBounce(b, n * -1);
          continue;
        }
        if (b.kind == ObjKind.star) {
          _starHit(b);
          _softBounce(a, n);
          continue;
        }
        if (a.hanging && bFall) _unhook(a, b.vel);
        if (b.hanging && aFall) _unhook(b, a.vel);
        if (!a.hanging) a.pos += n * ((minD - dist) * 0.5);
        if (!b.hanging) b.pos -= n * ((minD - dist) * 0.5);
        final rel = a.vel - b.vel;
        final sep = rel.dx * n.dx + rel.dy * n.dy;
        if (sep < 0) {
          final imp = n * sep * 0.45;
          if (!a.hanging) a.vel -= imp;
          if (!b.hanging) b.vel += imp;
        }
      }
    }

    if (burst) {
      burstLeft -= dt;
      if (burstLeft <= 0) burst = false;
    }
    if (burstFlash > 0) burstFlash = max(0, burstFlash - dt * 2);

    for (final f in floaters) {
      f.life -= dt;
      f.pos = Offset(f.pos.dx, f.pos.dy - 0.08 * dt);
    }
    floaters.removeWhere((f) => f.life <= 0);

    for (final s in sparks) {
      s.life -= dt;
      s.vel = Offset(s.vel.dx * (1 - dt * 0.7), s.vel.dy + 0.28 * dt);
      s.pos += s.vel * dt;
    }
    sparks.removeWhere((s) => s.life <= 0);

    if (chainDecay > 0) {
      chainDecay -= dt;
      if (chainDecay <= 0) chainWindow = 0;
    }

    if (started) {
      if (!moving) {
        still += dt;
      } else {
        still = 0;
      }
      final falling = objects.where((o) => !o.scenery && !o.collected && !o.hanging);
      final hangingLeft = objects.any((o) =>
          !o.scenery &&
          !o.collected &&
          o.hanging &&
          o.kind != ObjKind.bell &&
          o.kind != ObjKind.star);
      if (falling.isEmpty && (launchesLeft <= 0 || !hangingLeft) && still > 0.5) {
        ended = true;
      }
      if (missed >= missCap && falling.isEmpty && still > 0.3) {
        ended = true;
      }
    }
  }

  void _unhook(FieldObj o, Offset from) {
    if (o.scenery || o.collected || !o.hanging) return;
    if (o.kind == ObjKind.bell || o.kind == ObjKind.star) return;
    o.hanging = false;
    o.vel = Offset(
      (from.dx * 0.28) + (rng.nextDouble() - 0.5) * 0.12,
      max(0.06, from.dy.abs() * 0.18),
    );
    o.spinVel = (rng.nextDouble() - 0.5) * 3.2;
    o.glow = 0.7;
    chain += 1;
    chainWindow += 1;
    chainDecay = 1.8;
    _pop(o.pos, Lf.goldHot, 4);
    if (chainWindow >= 3 && chainWindow % 3 == 0) {
      floaters.add(FieldFloater('CHAIN x$chainWindow', o.pos, 1.0, Lf.goldHot, big: true));
    }
    AudioHub.I.play(Sfx.chain);
  }

  void _bellHit(FieldObj bell, Offset from) {
    bell.glow = 1;
    bell.ringPulse = 1;
    bell.ringTilt = (from.dx >= 0 ? 0.85 : -0.85);
    AudioHub.I.play(Sfx.bell);
    if (!bell.rung) {
      bell.rung = true;
      bellsRung += 1;
      collected.add(bell.collectId);
    }
    _pop(bell.pos, Lf.goldHot, 10);
    floaters.add(FieldFloater('Clang!', bell.pos, 0.75, Lf.goldHot, big: true));
  }

  void _bounceOffBell(FieldObj o, FieldObj bell) {
    if (o.hanging || o.fixed) return;
    final side = (o.pos.dx - bell.pos.dx);
    final away = side.abs() < 0.008 ? (rng.nextBool() ? 1.0 : -1.0) : side.sign;
    o.vel = Offset(away * (0.26 + rng.nextDouble() * 0.12), -0.58 - rng.nextDouble() * 0.10);
    o.pos = Offset((o.pos.dx + away * 0.035).clamp(0.14, 0.86), o.pos.dy - 0.025);
    o.spinVel += away * 5.5;
    o.glow = 0.55;
    _pop(o.pos, Lf.goldHot, 5);
  }

  void _starHit(FieldObj star) {
    if (star.rung) {
      star.glow = 1;
      return;
    }
    star.rung = true;
    star.glow = 1;
    starHit = true;
    burst = true;
    burstFlash = 1;
    burstLeft = 4.5 + game.starLv * 0.4;
    collected.add(star.collectId);
    AudioHub.I.play(Sfx.star);
    _addScore(star.value, star.pos, Lf.goldHot);
    _pop(star.pos, Lf.goldHot, 14);
    floaters.add(FieldFloater('BURST!', star.pos, 1.1, Lf.goldHot, big: true));
    for (var i = 0; i < 3 + game.starLv ~/ 2; i++) {
      final coin = FieldObj(
        kind: ObjKind.coin,
        sprite: A.coinStar,
        collectId: 'coin_sun',
        pos: star.pos + Offset((rng.nextDouble() - 0.5) * 0.12, -0.02),
        radius: 0.028,
        value: 16,
        hanging: false,
      )..vel = Offset((rng.nextDouble() - 0.5) * 0.22, 0.04);
      objects.add(coin);
    }
  }

  void _softBounce(FieldObj o, Offset n) {
    if (o.hanging || o.fixed) return;
    o.vel = Offset(o.vel.dx + n.dx * 0.28, max(0.08, o.vel.dy * 0.35 + 0.08));
    o.spinVel += (rng.nextDouble() - 0.5) * 2.4;
  }

  void _catch(FieldObj o) {
    if (o.collected || o.scenery) return;
    o.collected = true;
    caught += 1;
    collected.add(o.collectId);
    catchFlash = 1;
    final perfect = (o.pos.dx - basketX).abs() < basketHalf * 0.38;
    final bonus = 1 + (chainWindow > 3 ? chainWindow - 3 : 0) + (perfect ? 1 : 0);
    final value = (o.value * bonus).clamp(o.value, o.value * 5);
    _addScore(value, Offset(basketX, basketY - 0.06), perfect ? Lf.goldHot : Lf.leaf);
    _pop(Offset(basketX, basketY - 0.05), perfect ? Lf.goldHot : Lf.leaf, perfect ? 10 : 6);
    if (perfect) {
      floaters.add(FieldFloater('Perfect!', Offset(basketX, basketY - 0.10), 0.9, Lf.goldHot, big: true));
    }
    if (o.kind == ObjKind.emblem) rGot += 1;
    AudioHub.I.play(o.kind == ObjKind.coin ? Sfx.coin : Sfx.fruit);
  }

  void _miss(FieldObj o) {
    if (o.countedMiss || o.collected) return;
    o.countedMiss = true;
    o.collected = true;
    missed += 1;
    floaters.add(FieldFloater('Miss', Offset(o.pos.dx, basketY - 0.02), 0.8, Lf.berry));
    _pop(Offset(o.pos.dx, basketY), Lf.berry, 4);
  }

  void _addScore(int v, Offset p, Color c, {String? text}) {
    if (v == 0 && text == null) return;
    var vv = v;
    if (burst) vv = (vv * game.starMult).round();
    vv = (vv * game.chainBonus).round();
    if (vv > 0) {
      score += vv;
      coinsGot += max(1, vv ~/ 8);
    }
    floaters.add(FieldFloater(text ?? '+$vv', p, 1.0, c));
  }

  void _pop(Offset p, Color color, int n) {
    final count = min(n, 10);
    for (var i = 0; i < count; i++) {
      final a = rng.nextDouble() * pi * 2;
      final speed = 0.12 + rng.nextDouble() * 0.22;
      sparks.add(FieldSpark(
        p,
        Offset(cos(a) * speed, sin(a) * speed - 0.1),
        0.4 + rng.nextDouble() * 0.22,
        color,
        2.2 + rng.nextDouble() * 2.2,
      ));
    }
  }

  // ---------------- Input ----------------

  void _onPointerDown(Offset local, Size size) {
    if (paused || ended) return;
    _pointerDown = local;
    _didDrag = false;
  }

  void _onPointerMove(Offset local, Size size) {
    if (paused || ended) return;
    if (_pointerDown != null && (local - _pointerDown!).distance > 8) _didDrag = true;
    _moveBasket(local, size);
    fieldTick.value++;
  }

  void _onPointerUp(Offset local, Size size) {
    if (paused || ended) return;
    final start = _pointerDown;
    _pointerDown = null;
    if (_didDrag || start == null) return;
    if (local.dy > size.height * 0.78 || local.dy < 80) return;
    _tapPiece(local, size);
  }

  void _moveBasket(Offset local, Size size) {
    final nx = (local.dx / size.width).clamp(basketHalf, 1 - basketHalf);
    basketLean = ((nx - basketX) * 6).clamp(-0.22, 0.22);
    basketX = nx;
  }

  void _tapPiece(Offset local, Size size) {
    if (launchesLeft <= 0) return;
    final p = Offset(local.dx / size.width, local.dy / size.height);
    FieldObj? best;
    var bestD = 0.11;
    for (final o in objects) {
      if (o.scenery || o.collected || !o.hanging || o.fixed) continue;
      if (o.kind == ObjKind.bell || o.kind == ObjKind.star) continue;
      final d = (o.pos - p).distance;
      if (d < bestD) {
        bestD = d;
        best = o;
      }
    }
    if (best == null) return;
    started = true;
    launchesLeft -= 1;
    game.markTip();
    _unhook(best, const Offset(0, 0.28));
    AudioHub.I.play(Sfx.fruit);
    AudioHub.I.haptic();
    _bumpHud();
  }

  // ---------------- Finish ----------------

  void _finish() {
    if (_closing) return;
    _closing = true;
    ended = true;
    final success = caught >= quota && missed <= missCap;
    final stars = starsFor(
      chain: chain,
      caught: caught,
      missed: missed,
      goal: quota,
      chainGoal: zone.minChain + widget.day,
      success: success,
    );
    AudioHub.I.play(success ? Sfx.victory : Sfx.defeat);
    final result = DayResult(
      zoneId: zone.id,
      day: widget.day,
      score: score,
      chain: chain,
      caught: caught,
      missed: missed,
      coins: coinsGot,
      rGained: rGot,
      starHit: starHit,
      burst: starHit,
      collected: List.of(collected),
      bells: bellsRung,
      stars: stars,
      success: success,
    );
    game.applyRun(result);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(FadeRoute(ResultScreen(result: result, zone: zone)));
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) setState(() => paused = true);
      },
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _onPointerDown(e.localPosition, size),
              onPointerMove: (e) => _onPointerMove(e.localPosition, size),
              onPointerUp: (e) => _onPointerUp(e.localPosition, size),
              onPointerCancel: (_) => _pointerDown = null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverBg(zone.background),
                  if (_ready)
                    ListenableBuilder(
                      listenable: fieldTick,
                      builder: (_, _) => CustomPaint(
                        painter: FieldPainter(
                          objects: objects,
                          sparks: sparks,
                          floaters: floaters,
                          images: store.images,
                          alpha: _alpha,
                          basketX: basketX,
                          basketY: basketY,
                          basketHalf: basketHalf,
                          basketLean: basketLean,
                          catchFlash: catchFlash,
                          wind: wind,
                          frame: fieldTick.value,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                      child: ListenableBuilder(
                        listenable: hudTick,
                        builder: (_, _) => Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FittedBox(
                                    alignment: Alignment.centerLeft,
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      children: [
                                        _StatChip(icon: Icons.bolt_rounded, value: '$chain', tint: Lf.goldHot),
                                        const SizedBox(width: 6),
                                        _StatChip(
                                          icon: Icons.shopping_basket_rounded,
                                          value: '$caught/$quota',
                                          tint: Lf.leaf,
                                        ),
                                        const SizedBox(width: 6),
                                        _StatChip(
                                          icon: Icons.close_rounded,
                                          value: '${min(missed, missCap)}/$missCap',
                                          tint: Lf.berry,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                RoundIconBtn(
                                  icon: Icons.pause_rounded,
                                  onTap: () => setState(() => paused = true),
                                ),
                              ],
                            ),
                            if (burst || wind.abs() > 0.15) ...[
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (wind.abs() > 0.15)
                                    _WindPill(dir: wind),
                                  if (burst) ...[
                                    if (wind.abs() > 0.15) const SizedBox(width: 6),
                                    _BurstPill(mult: game.starMult),
                                  ],
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            _LaunchBar(left: launchesLeft, total: 2 + (widget.day > 1 ? 1 : 0) + (game.chainLv >= 3 ? 1 : 0)),
                            if (!started && !game.seenTip)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: WoodPanel(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  child: Text(
                                    'Tap a fruit to drop it • dodge the wandering bells — they bounce fruit up',
                                    textAlign: TextAlign.center,
                                    style: Lf.body.copyWith(fontSize: 14),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (paused)
                    _Pause(
                      zone: zone,
                      day: widget.day,
                      onResume: () => setState(() => paused = false),
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

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.value, required this.tint});
  final IconData icon;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xCC1A140C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.75), width: 1.4),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: 4),
          Text(value, style: Lf.title.copyWith(fontSize: 13, color: Colors.white)),
        ],
      ),
    );
  }
}

class _WindPill extends StatelessWidget {
  const _WindPill({required this.dir});
  final double dir;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xCC1E5A88),
        border: Border.all(color: Lf.sky),
      ),
      child: Text(
        dir > 0 ? 'WIND →' : '← WIND',
        style: Lf.title.copyWith(fontSize: 12, color: Colors.white),
      ),
    );
  }
}

class _BurstPill extends StatelessWidget {
  const _BurstPill({required this.mult});
  final double mult;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(colors: [Color(0xFFFFE27A), Color(0xFFF5C542)]),
        boxShadow: const [BoxShadow(color: Color(0xAAFFC938), blurRadius: 10)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 15, color: Color(0xFF1A140C)),
          const SizedBox(width: 4),
          Text(
            'BURST x${mult.toStringAsFixed(1)}',
            style: Lf.title.copyWith(fontSize: 12, color: const Color(0xFF1A140C)),
          ),
        ],
      ),
    );
  }
}

class _LaunchBar extends StatelessWidget {
  const _LaunchBar({required this.left, required this.total});
  final int left;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final on = i < left;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 22,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: on
                  ? const LinearGradient(colors: [Color(0xFFFFE27A), Color(0xFFF5C542)])
                  : null,
              color: on ? null : Colors.white24,
              boxShadow: on ? const [BoxShadow(color: Color(0x88FFC938), blurRadius: 6)] : null,
            ),
          ),
        );
      }),
    );
  }
}

class _Pause extends StatelessWidget {
  const _Pause({required this.onResume, required this.zone, required this.day});
  final VoidCallback onResume;
  final ZoneDef zone;
  final int day;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: WoodPanel(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: SizedBox(
            width: 240,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TitleBanner('Paused'),
                const SizedBox(height: 16),
                GroveButton(label: 'RESUME', width: 200, onTap: onResume),
                const SizedBox(height: 10),
                GroveButton(
                  label: 'RESTART',
                  width: 200,
                  color: Lf.goldDark,
                  dark: const Color(0xFF7A560C),
                  onTap: () {
                    Navigator.of(context).pushReplacement(
                      FadeRoute(GameplayScreen(zone: zone, day: day)),
                    );
                  },
                ),
                const SizedBox(height: 10),
                GroveButton(
                  label: 'SETTINGS',
                  width: 200,
                  color: Lf.sky,
                  dark: const Color(0xFF1E5A88),
                  onTap: () => Navigator.push(context, FadeRoute(const SettingsScreen())),
                ),
                const SizedBox(height: 10),
                GroveButton(
                  label: 'MAIN MENU',
                  width: 200,
                  color: Lf.berry,
                  dark: const Color(0xFF7A2438),
                  onTap: () {
                    AudioHub.I.close();
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
