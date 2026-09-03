import 'dart:convert';

import '../routing.dart';
import '../settings.dart';
import 'local_vault.dart';
import 'prism_http.dart';

// ─────────────────────────────────────────────────────────────
// RULING ENDPOINT — POST the assembled body, cache the answer
// ─────────────────────────────────────────────────────────────
// The backend is the single source of truth for the routing
// decision. On an approved response we cache both the URL AND
// its expiry so returning launches can skip the network call
// when the URL is still fresh. On any failure — HTTP error,
// timeout, malformed JSON — we return a rejected ruling; the
// dispatcher converts that into a native route (or a no-link
// route when the adapter is down).
// ─────────────────────────────────────────────────────────────

class RulingEndpoint {
  RulingEndpoint(this._vault);

  final LocalVault _vault;

  Future<Ruling> query(Map<String, dynamic> body) async {
    final String endpoint = PrismSettings.rulingEndpoint;
    if (endpoint.isEmpty) {
      return Ruling.reject('endpoint_missing');
    }

    try {
      final response = await prismHttp
          .post(
            Uri.parse(endpoint),
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(
            Duration(seconds: PrismSettings.rulingTimeoutSeconds),
          );

      if (response.statusCode != 200) {
        return Ruling.reject('http_${response.statusCode}');
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) return Ruling.reject('malformed');
      final Ruling ruling = Ruling.fromJson(
        Map<String, dynamic>.from(decoded),
      );

      if (ruling.hasTarget) {
        await _vault.writeTarget(ruling.url!, ruling.expiresAt);
      }
      return ruling;
    } catch (e) {
      return Ruling.reject('network:$e');
    }
  }
}
