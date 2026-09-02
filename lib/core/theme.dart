import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Lf {
  static const deep = Color(0xFF143018);
  static const forest = Color(0xFF1F4A24);
  static const meadow = Color(0xFF3E8B3A);
  static const leaf = Color(0xFF6BCB4A);
  static const gold = Color(0xFFF5C542);
  static const goldHot = Color(0xFFFFE27A);
  static const goldDark = Color(0xFFC48A14);
  static const wood = Color(0xFF8B5A2B);
  static const woodDark = Color(0xFF5A3516);
  static const cream = Color(0xFFFFF6D8);
  static const berry = Color(0xFFC43B5A);
  static const sky = Color(0xFF4AA3E6);
  static const ink = Color(0xFF1A140C);

  static const title = TextStyle(
    fontFamily: 'Fredoka',
    fontWeight: FontWeight.w700,
    color: cream,
    height: 1.05,
  );

  static const body = TextStyle(
    fontFamily: 'Nunito',
    fontWeight: FontWeight.w700,
    color: cream,
    height: 1.2,
  );

  static ThemeData theme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: deep,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        secondary: leaf,
        surface: forest,
      ),
      fontFamily: 'Nunito',
      splashFactory: NoSplash.splashFactory,
    );
  }
}

void hideChrome() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
}

Future<void> lockPortrait() {
  return SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
}

Future<void> unlockOrientation() {
  return SystemChrome.setPreferredOrientations(DeviceOrientation.values);
}
