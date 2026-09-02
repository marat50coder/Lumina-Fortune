import 'package:flutter/material.dart';

class FadeRoute<T> extends PageRouteBuilder<T> {
  FadeRoute(Widget page, {this.ms = 380})
      : super(
          pageBuilder: (_, _, _) => page,
          transitionDuration: Duration(milliseconds: ms),
          reverseTransitionDuration: Duration(milliseconds: (ms * 0.75).round()),
          transitionsBuilder: (_, anim, _, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
              child: child,
            );
          },
        );

  final int ms;
}
