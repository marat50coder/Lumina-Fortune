import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'assets.dart';

class AudioHub {
  AudioHub._();
  static final AudioHub I = AudioHub._();

  final AudioPlayer _a = AudioPlayer();
  final AudioPlayer _b = AudioPlayer();
  bool sfx = true;
  bool music = true;
  bool vibrate = true;
  bool _flip = false;

  Future<void> play(String asset) async {
    if (!sfx) return;
    final p = _flip ? _a : _b;
    _flip = !_flip;
    try {
      await p.stop();
      await p.play(AssetSource(asset), volume: 0.88);
    } catch (_) {}
  }

  Future<void> click() => play(Sfx.click);
  Future<void> open() => play(Sfx.menuOpen);
  Future<void> close() => play(Sfx.menuClose);

  void haptic() {
    if (!vibrate) return;
    HapticFeedback.lightImpact();
  }

  Future<void> dispose() async {
    await _a.dispose();
    await _b.dispose();
  }
}
