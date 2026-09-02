import 'dart:math';

import 'package:flutter/material.dart';

enum ObjKind { fruit, berry, coin, bell, star, emblem, golden, seed, scenery }

class FieldObj {
  FieldObj({
    required this.kind,
    required this.sprite,
    required this.collectId,
    required this.pos,
    required this.radius,
    required this.value,
    this.hanging = true,
    this.scenery = false,
    this.fixed = false,
    Offset? tether,
  }) : tether = tether ?? pos,
       prevPos = pos;

  final ObjKind kind;
  final String sprite;
  final String collectId;
  Offset pos;
  Offset prevPos;
  Offset vel = Offset.zero;
  double spin = 0;
  double spinVel = 0;
  final double radius;
  final int value;
  Offset tether;
  bool hanging;
  bool scenery;
  bool fixed;
  bool collected = false;
  bool countedMiss = false;
  bool rung = false;
  double wobble = Random().nextDouble() * pi * 2;
  double glow = 0;
  double life = 0;
  double stuck = 0;
  double ringTilt = 0;
  double ringPulse = 0;
}

class FieldSpark {
  FieldSpark(this.pos, this.vel, this.life, this.color, this.size, {this.leaf = false});
  Offset pos;
  Offset vel;
  double life;
  final Color color;
  final double size;
  final bool leaf;
}

class FieldFloater {
  FieldFloater(this.text, this.pos, this.life, this.color, {this.big = false});
  final String text;
  Offset pos;
  double life;
  final Color color;
  final bool big;
}
