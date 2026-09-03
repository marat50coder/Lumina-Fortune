// ─────────────────────────────────────────────────────────────
// ROUTING — sealed outcome types for the prism boot pipeline
// ─────────────────────────────────────────────────────────────
// The dispatcher pipeline outputs ONE of three sealed subtypes.
// The warmup screen destructures via `switch` and only then
// decides which screen to push. That pattern replaces the older
// pattern where each network branch could independently push a
// route — you can no longer forget a case, and adding a fourth
// outcome forces a change at every dispatch site.
// ─────────────────────────────────────────────────────────────

/// Persisted routing memory across launches.
///
/// Wire values are stored under a project-scoped keystore key.
/// Do NOT rename the wire spellings — legacy installs still hold
/// the old strings.
enum RouteMemo {
  fresh,
  webShell,
  nativeGame;

  String get wire => switch (this) {
        RouteMemo.fresh => 'fresh',
        RouteMemo.webShell => 'web',
        RouteMemo.nativeGame => 'native',
      };

  static RouteMemo parse(String? raw) => switch (raw) {
        'web' || 'portal' || 'shell' => RouteMemo.webShell,
        'native' || 'game' => RouteMemo.nativeGame,
        _ => RouteMemo.fresh,
      };
}

/// Parsed response from the ruling endpoint. Wire keys are
/// `{ok, url, expires, message}` — preserved verbatim (backend
/// contract).
class Ruling {
  const Ruling({
    required this.approved,
    this.url,
    this.expiresAt,
    this.note,
  });

  factory Ruling.fromJson(Map<String, dynamic> json) {
    final dynamic exp = json['expires'];
    return Ruling(
      approved: json['ok'] == true,
      url: json['url'] is String ? json['url'] as String : null,
      expiresAt:
          exp is num ? exp.toInt() : int.tryParse(exp?.toString() ?? ''),
      note: json['message']?.toString(),
    );
  }

  factory Ruling.reject(String note) => Ruling(approved: false, note: note);

  final bool approved;
  final String? url;
  final int? expiresAt;
  final String? note;

  bool get hasTarget => approved && url != null && url!.isNotEmpty;
}

/// Sealed outcome of the boot pipeline. Warmup destructures via
/// `switch` and cannot forget a branch.
sealed class PrismRoute {
  const PrismRoute();
}

/// Show the native white-part game.
final class NativeRoute extends PrismRoute {
  const NativeRoute();
}

/// Show the WebView shell at [url]. `coldTap` is true only when
/// the launch was triggered by a cold-boot push tap (URL from
/// the intent payload) — the warmup animation should shorten.
final class ShellRoute extends PrismRoute {
  const ShellRoute(this.url, {this.coldTap = false});

  final String url;
  final bool coldTap;
}

/// Show the no-link screen. Retry rebuilds the boot pipeline.
final class NoLinkRoute extends PrismRoute {
  const NoLinkRoute({required this.canFallToGame});

  final bool canFallToGame;
}
