import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────
// DIAG — debug-only tracing for the prism (gray) pipeline.
// ─────────────────────────────────────────────────────────────
// Every gray-flow breadcrumb goes through [plog]. In a release
// build `kDebugMode` is a compile-time `false`, so the closure is
// never invoked and nothing — endpoint, request body, attribution
// payload, push token — can reach logcat. The message is built
// lazily so release builds pay zero string-interpolation cost.
//
// Rule: NEVER call `print`/`debugPrint` directly in lib/prism.
// Route everything through `plog` so the release binary is silent
// (FINAL_CHECKLIST Part G / play-moderation logging invariant).
// ─────────────────────────────────────────────────────────────

void plog(String Function() message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(message());
  }
}
