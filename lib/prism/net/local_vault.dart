import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routing.dart';
import '../settings.dart';

const String _pfx = 'kpx9_';

class LocalVault {
  LocalVault({FlutterSecureStorage? sealed})
      : _sealed = sealed ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: false,
              ),
            );

  static const String _kRoute = '${_pfx}route';
  static const String _kTarget = '${_pfx}target';
  static const String _kTargetTtl = '${_pfx}target_ttl';
  static const String _kInviteUntil = '${_pfx}invite_until';
  static const String _kInviteAccepted = '${_pfx}invite_ok';
  static const String _kInviteOsBlocked = '${_pfx}invite_os_deny';
  static const String _kPendingUrl = '${_pfx}pending';

  SharedPreferences? _bench;
  final FlutterSecureStorage _sealed;

  Future<void> warm() async {
    _bench = await SharedPreferences.getInstance()
        .timeout(const Duration(seconds: 2));
  }

  RouteMemo get route => RouteMemo.parse(_bench?.getString(_kRoute));

  Future<void> storeRoute(RouteMemo r) async {
    await _bench?.setString(_kRoute, r.wire);
  }

  Future<String?> cachedTarget() => _readSealed(_kTarget);

  Future<void> writeTarget(String url, int? expiresUnix) async {
    await _writeSealed(_kTarget, url);
    final int ttl = expiresUnix ??
        (_nowSecs() + PrismSettings.cacheLifetimeSeconds);
    await _bench?.setInt(_kTargetTtl, ttl);
  }

  bool get cachedTargetExpired {
    final int? until = _bench?.getInt(_kTargetTtl);
    if (until == null) return true;
    return _nowSecs() >= until;
  }

  bool get inviteAccepted => _bench?.getBool(_kInviteAccepted) ?? false;

  Future<void> markInviteAccepted(bool v) async {
    await _bench?.setBool(_kInviteAccepted, v);
  }

  bool get inviteOsBlocked => _bench?.getBool(_kInviteOsBlocked) ?? false;

  Future<void> markInviteOsBlocked() async {
    await _bench?.setBool(_kInviteOsBlocked, true);
  }

  Future<void> writeInviteSnoozeUntil(int unixSecs) async {
    await _bench?.setInt(_kInviteUntil, unixSecs);
  }

  bool get shouldShowInvite {
    if (inviteAccepted) return false;
    if (inviteOsBlocked) return false;
    final int? until = _bench?.getInt(_kInviteUntil);
    if (until == null) return true;
    return _nowSecs() >= until;
  }

  Future<void> stashPending(String? url) async {
    if (url == null || url.isEmpty) {
      try {
        await _sealed
            .delete(key: _kPendingUrl)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    } else {
      await _writeSealed(_kPendingUrl, url);
    }
  }

  Future<String?> takePending() async {
    final String? url = await _readSealed(_kPendingUrl);
    if (url != null) {
      try {
        await _sealed
            .delete(key: _kPendingUrl)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    return url;
  }

  Future<String?> _readSealed(String key) async {
    try {
      return await _sealed.read(key: key).timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSealed(String key, String value) async {
    try {
      await _sealed
          .write(key: key, value: value)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  static int _nowSecs() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
