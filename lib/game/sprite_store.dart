import 'dart:ui' as ui;

import 'package:flutter/services.dart';

class SpriteStore {
  final images = <String, ui.Image>{};

  Future<void> load(Iterable<String> paths) async {
    final unique = paths.toSet().where((p) => p.isNotEmpty && !images.containsKey(p));
    await Future.wait(unique.map((path) async {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      images[path] = (await codec.getNextFrame()).image;
    }));
  }
}
