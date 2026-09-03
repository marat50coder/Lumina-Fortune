import 'package:webview_flutter/webview_flutter.dart';

import '../sealed_bytes.dart';

// ─────────────────────────────────────────────────────────────
// WEB INJECTORS — assembled JavaScript enhancers
// ─────────────────────────────────────────────────────────────
// Every JS body ships as a sealed byte array in `sealed_bytes.dart`.
// The runtime unseals and runs each one on `onPageFinished`. All
// enhancers are idempotent via a `window.__lf*` sentinel flag so
// they no-op on re-injection.
//
// Safe-area rules: the body ONLY touches the site's own CSS
// variables and a small allow-list of decorative header classes.
// Never `html`, `body`, `#app`, `#root`. See .cursor rules →
// webview_safe_area_injection.mdc.
// ─────────────────────────────────────────────────────────────

class WebInjectors {
  WebInjectors._();

  /// Install the enhancer sequence on the given controller.
  /// Called from `WebShell.onPageFinished` and safe to invoke on
  /// every navigation (each body has its own sentinel guard).
  static Future<void> installAll(WebViewController controller) async {
    for (final String body in _bodies()) {
      if (body.isEmpty) continue;
      try {
        await controller.runJavaScript(body);
      } catch (_) {
        // A single misbehaving body must not break the load.
      }
    }
  }

  static List<String> _bodies() => <String>[
        unsealJsSafeArea(),
        unsealJsKeyboard(),
        unsealJsAutoplay(),
      ];
}
