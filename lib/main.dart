import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/loading_screen.dart';
import 'state/game_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  hideChrome();
  unlockOrientation();
  runApp(const LuminaFortuneApp());
}

class LuminaFortuneApp extends StatelessWidget {
  const LuminaFortuneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GameController(),
      child: MaterialApp(
        title: 'Lumina Fortune',
        debugShowCheckedModeBanner: false,
        theme: Lf.theme(),
        home: const LoadingScreen(),
      ),
    );
  }
}
