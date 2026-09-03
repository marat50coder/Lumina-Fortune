import 'package:http/http.dart' as http;

import 'ua_forger.dart';

// ─────────────────────────────────────────────────────────────
// PRISM HTTP — http.Client that always carries the forged UA
// ─────────────────────────────────────────────────────────────
// Every outbound HTTP call in the prism pipeline (ruling POST,
// GCD rescue, push image fetch) goes through this client. The
// User-Agent header is written unconditionally so no request
// leaks the default Dart `dart-io/x.y` token — that literal is
// a trivial Flutter-shell tell.
// ─────────────────────────────────────────────────────────────

class PrismHttp extends http.BaseClient {
  PrismHttp();

  final http.Client _underlying = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['User-Agent'] = UaForger.value;
    return _underlying.send(request);
  }

  @override
  void close() => _underlying.close();
}

/// Shared client instance. Constructed once after `UaForger.prime()`
/// completes in `main()`.
final PrismHttp prismHttp = PrismHttp();
