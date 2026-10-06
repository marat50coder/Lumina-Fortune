import '../diag.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_vault.dart';
import 'prism_http.dart';

// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// PUSH GATE вЂ” Firebase Messaging + local notifications
// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// Cold-start taps are parked in the vault inside [ignite] BEFORE
// the dispatcher reads them. Reading the vault first would replay
// a stale URL from a previous notification.
//
// Each tray entry uses a unique id (FCM messageId, else a clock
// stamp) so two pushes never overwrite each other.
// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

const String kPushChannelId = 'lf_glow_stream';
const String kPushChannelName = 'Glow updates';
const String _smallIcon = '@drawable/ic_flame_notify';

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  kPushChannelId,
  kPushChannelName,
  description: 'News and offers about the game',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  enableLights: true,
  showBadge: true,
);

const List<String> _urlKeys = <String>[
  'url',
  'deep_link',
  'deeplink',
  'deep_link_value',
  'deep_link_sub1',
  'af_dp',
  'af_web_dp',
  'target',
  'link',
  'landing',
  'click_url',
  'href',
];

const List<String> _nestedBoxes = <String>['payload', 'data', 'aps'];

@pragma('vm:entry-point')
Future<void> prismBgPush(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
  // OS already draws the system tray row when a notification
  // payload is present. Data-only messages need a local post.
  if (message.notification != null) return;
  await postGlowTray(message);
}

String? pluckGlowUrl(Map<String, dynamic> data) {
  for (final MapEntry<String, dynamic> entry in data.entries) {
    if (!_urlKeys.contains(entry.key.toLowerCase())) continue;
    final Object? value = entry.value;
    if (value is String && value.trim().isNotEmpty) {
      final String trimmed = value.trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
    }
  }
  for (final String box in _nestedBoxes) {
    final Object? nested = data[box];
    if (nested is Map) {
      final String? found = pluckGlowUrl(Map<String, dynamic>.from(nested));
      if (found != null) return found;
    } else if (nested is String && nested.trim().isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(nested);
        if (decoded is Map) {
          final String? found = pluckGlowUrl(
            Map<String, dynamic>.from(decoded),
          );
          if (found != null) return found;
        }
      } catch (_) {}
    }
  }
  return null;
}

int _trayStamp(RemoteMessage message) {
  final String? id = message.messageId;
  if (id != null && id.isNotEmpty) {
    return id.hashCode & 0x7fffffff;
  }
  final int sent = message.sentTime?.millisecondsSinceEpoch ?? 0;
  final int mix = sent ^ DateTime.now().microsecondsSinceEpoch;
  final int stamp = mix & 0x7fffffff;
  return stamp == 0 ? 1 : stamp;
}

Future<void> postGlowTray(RemoteMessage message) async {
  final RemoteNotification? note = message.notification;
  final String? title = note?.title ??
      message.data['title'] as String? ??
      message.data['Title'] as String?;
  final String? body = note?.body ??
      message.data['body'] as String? ??
      message.data['Body'] as String?;
  if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
    return;
  }

  final FlutterLocalNotificationsPlugin tray =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings android =
      AndroidInitializationSettings(_smallIcon);
  await tray.initialize(const InitializationSettings(android: android));

  if (Platform.isAndroid) {
    final AndroidFlutterLocalNotificationsPlugin? plugin = tray
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await plugin?.createNotificationChannel(_channel);
  }

  AndroidNotificationDetails? details;
  final String? picture =
      note?.android?.imageUrl ?? message.data['image'] as String?;
  if (picture != null && picture.isNotEmpty) {
    final Uint8List? bytes = await _grabImage(picture);
    if (bytes != null) {
      details = AndroidNotificationDetails(
        kPushChannelId,
        kPushChannelName,
        importance: Importance.max,
        priority: Priority.max,
        icon: _smallIcon,
        styleInformation: BigPictureStyleInformation(
          ByteArrayAndroidBitmap(bytes),
          largeIcon:
              const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
      );
    }
  }

  details ??= const AndroidNotificationDetails(
    kPushChannelId,
    kPushChannelName,
    importance: Importance.max,
    priority: Priority.max,
    icon: _smallIcon,
    category: AndroidNotificationCategory.message,
    fullScreenIntent: false,
    visibility: NotificationVisibility.public,
    channelShowBadge: true,
    enableVibration: true,
    enableLights: true,
    playSound: true,
    ticker: 'ticker',
  );

  final Map<String, dynamic> payload = Map<String, dynamic>.from(message.data);
  final String? url = pluckGlowUrl(payload);
  if (url != null) payload['url'] = url;

  await tray.show(
    _trayStamp(message),
    title,
    body,
    NotificationDetails(android: details),
    payload: payload.isNotEmpty ? jsonEncode(payload) : url,
  );
}

Future<Uint8List?> _grabImage(String url) async {
  try {
    final res = await prismHttp
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return res.bodyBytes;
  } catch (_) {}
  return null;
}

class PushGate {
  PushGate(this._vault);

  final LocalVault _vault;
  final FlutterLocalNotificationsPlugin _tray =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _fm;
  String? _token;
  bool _ready = false;
  Future<void>? _igniting;
  bool _launchUrlParked = false;

  final Queue<String> _spool = Queue<String>();
  void Function(String url)? _sink;
  void Function(String token)? onTokenRotate;

  String? get token => _token;

  void Function(String url)? get onWarmUrl => _sink;
  set onWarmUrl(void Function(String url)? cb) {
    _sink = cb;
    if (cb == null) return;
    while (_spool.isNotEmpty) {
      cb(_spool.removeFirst());
    }
  }

  Future<void> ignite() {
    if (_ready) return Future<void>.value();
    return _igniting ??= _ignite().whenComplete(() {
      if (!_ready) _igniting = null;
    });
  }

  Future<void> _ignite() async {
    plog(() => '[LF/PUSH] ignite.start');
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _fm = FirebaseMessaging.instance;
      // Fast listener wiring вЂ” these just register Dart callbacks
      // with the native side, no I/O.
      FirebaseMessaging.onMessage.listen((RemoteMessage m) {
        plog(() => '[LF/PUSH] foreground id=${m.messageId} '
            'notif=${m.notification?.title} data=${m.data}');
        _onForeground(m);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage m) {
        plog(() => '[LF/PUSH] warmTap id=${m.messageId} data=${m.data}');
        _onWarmTap(m);
      });
      _fm!.onTokenRefresh.listen((String t) {
        _token = t;
        plog(() => '[LF/PUSH] token.rotate len=${t.length}');
        onTokenRotate?.call(t);
      });
      // Cold-tap ingest from the launch intent is cheap вЂ” the
      // dispatcher reads it right after, so keep it inline.
      await _ingestLaunchTap();

      _ready = true;
      // Everything below is fire-and-forget. _prepTray and
      // getInitialMessage used to add 4вЂ“7 s to the critical path
      // on first launch for no routing benefit вЂ” pushes that
      // arrive while they are still warming are either queued
      // by the OS (notification payload) or handled by the bg
      // isolate (data payload).
      unawaited(_warmBackground());
    } catch (e, s) {
      plog(() => '[LF/PUSH] ignite.fail $e\n$s');
    }
  }

  Future<void> _warmBackground() async {
    try {
      await _fm?.setAutoInitEnabled(true);
    } catch (_) {}
    try {
      await _prepTray().timeout(const Duration(seconds: 4));
    } catch (_) {}
    if (!_launchUrlParked && _fm != null) {
      try {
        final RemoteMessage? initial = await _fm!
            .getInitialMessage()
            .timeout(const Duration(seconds: 3));
        if (initial != null) {
          plog(() => '[LF/PUSH] cold initial id=${initial.messageId} '
              'data=${initial.data}');
          await _parkCold(initial);
        }
      } catch (_) {}
    }
    unawaited(_fetchToken());
  }

  Future<void> _fetchToken() async {
    if (_fm == null) return;
    for (int step = 0; step < 3; step++) {
      try {
        final String? next =
            await _fm!.getToken().timeout(const Duration(seconds: 8));
        if (next != null && next.isNotEmpty) {
          _token = next;
          plog(() => '[LF/PUSH] token.first len=${next.length}');
          onTokenRotate?.call(next);
          return;
        }
      } catch (e) {
        plog(() => '[LF/PUSH] token.step$step.fail $e');
      }
      await Future<void>.delayed(Duration(milliseconds: 350 * (step + 1)));
    }
  }

  Future<void> _prepTray() async {
    const AndroidInitializationSettings android =
        AndroidInitializationSettings(_smallIcon);
    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _tray.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        final String? url = _urlFromPayload(r.payload);
        if (url != null) _handWarm(url);
      },
    );

    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          _tray.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_channel);
    }
  }

  Future<void> _ingestLaunchTap() async {
    try {
      final NotificationAppLaunchDetails? launch =
          await _tray.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp != true) return;
      final String? url = _urlFromPayload(
        launch!.notificationResponse?.payload,
      );
      if (url == null || url.isEmpty) return;
      await _vault.stashPending(url);
      _launchUrlParked = true;
    } catch (_) {}
  }

  String? _urlFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final String trimmed = payload.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    try {
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return pluckGlowUrl(Map<String, dynamic>.from(decoded));
      }
      if (decoded is String) {
        final String inner = decoded.trim();
        if (inner.startsWith('http://') || inner.startsWith('https://')) {
          return inner;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> requestSystemPermission() async {
    if (_fm == null) return false;
    final NotificationSettings settings = await _fm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final AuthorizationStatus status = settings.authorizationStatus;
    final bool granted = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
    await _vault.markInviteAccepted(granted);
    if (status == AuthorizationStatus.denied) {
      await _vault.markInviteOsBlocked();
    }
    return granted;
  }

  void _onForeground(RemoteMessage message) {
    unawaited(postGlowTray(message));
  }

  Future<void> _parkCold(RemoteMessage message) async {
    final String? url = pluckGlowUrl(message.data);
    if (url == null || url.isEmpty) return;
    await _vault.stashPending(url);
  }

  void _onWarmTap(RemoteMessage message) {
    final String? url = pluckGlowUrl(message.data);
    if (url == null || url.isEmpty) return;
    _handWarm(url);
  }

  void _handWarm(String url) {
    final void Function(String url)? cb = _sink;
    if (cb != null) {
      cb(url);
      return;
    }
    _spool.add(url);
    unawaited(_vault.stashPending(url));
  }
}
