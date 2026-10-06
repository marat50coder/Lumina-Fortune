import 'dart:convert';
import 'dart:isolate';

import '../diag.dart';
import '../native/prism_ffi.dart';
import '../routing.dart';
import 'local_vault.dart';
import 'ua_forger.dart';

// ─────────────────────────────────────────────────────────────
// RULING ENDPOINT — seal + POST through the native relay caller
// ─────────────────────────────────────────────────────────────
// The routing decision is made by the backend. The HTTPS call no
// longer happens in Dart: the assembled body is handed to
// `libprism_core.so` (`pr_route`), which seals it into the neutral
// relay envelope, POSTs it to the proxy, and returns the verdict
// JSON verbatim. The relay endpoint and the shared secret never
// leave native code. On any failure — missing library, transport
// error, the relay's 404 decoy, malformed JSON — we return a
// rejected ruling; the dispatcher turns that into a native route.
//
// The native call blocks while the request is in flight, so it
// runs inside `Isolate.run` to keep the UI thread free. The Rust
// side re-opens the library per isolate, so no handle crosses the
// isolate boundary.
// ─────────────────────────────────────────────────────────────

class RulingEndpoint {
  RulingEndpoint(this._vault);

  final LocalVault _vault;

  Future<Ruling> query(Map<String, dynamic> body) async {
    if (!PrismNative.isAvailable) {
      plog(() => '[LF/RULE] skip — native gate unavailable');
      return Ruling.reject('gate_unavailable');
    }

    final String bodyJson = jsonEncode(body);
    final String ua = UaForger.value;
    plog(() => '[LF/RULE] route via native gate');
    final Stopwatch sw = Stopwatch()..start();
    try {
      final String answer = await Isolate.run<String>(
        () => PrismNative.route(bodyJson, ua),
      );
      plog(() => '[LF/RULE] answer in ${sw.elapsedMilliseconds}ms '
          'len=${answer.length}');
      if (answer.isEmpty) return Ruling.reject('gate_empty');

      final dynamic decoded = jsonDecode(answer);
      if (decoded is! Map) return Ruling.reject('malformed');
      final Ruling ruling = Ruling.fromJson(
        Map<String, dynamic>.from(decoded),
      );

      if (ruling.hasTarget) {
        await _vault.writeTarget(ruling.url!, ruling.expiresAt);
      }
      return ruling;
    } catch (e) {
      plog(() => '[LF/RULE] fail in ${sw.elapsedMilliseconds}ms $e');
      return Ruling.reject('native:$e');
    }
  }
}
